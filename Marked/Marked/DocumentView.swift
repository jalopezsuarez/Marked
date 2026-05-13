import SwiftUI
import SwiftData
import UIKit
import Markdown

enum DocumentMode {
    case reader, editor
}

/// Captures every reader-style input that affects rendering. Used so a single
/// `.onChange` fires when any of them changes, replacing five separate observers.
private struct StyleSignature: Equatable {
    let theme: ReaderTheme
    let fontSize: Double
    let font: ReaderFont
    let justified: Bool
    let lineSpacing: Double
    let horizontalMargin: Double
}

struct DocumentView: View {
    let recent: RecentFile
    let initialMode: DocumentMode
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var settings = ReaderSettings.shared
    @State private var mode: DocumentMode

    init(recent: RecentFile, initialMode: DocumentMode = .reader) {
        self.recent = recent
        self.initialMode = initialMode
        _mode = State(initialValue: initialMode)
    }
    @State private var rawText: String = ""
    @State private var originalText: String = ""
    @State private var loadError: String?
    @State private var resolvedURL: URL?
    @State private var hasSecurityScope: Bool = false

    @State private var sections: [MarkdownSection] = []
    @State private var outline: [MarkdownOutlineEntry] = []
    @State private var scrollProgress: Double = 0
    @State private var jumpToSectionIndex: Int? = nil
    @State private var jumpToLine: Int? = nil

    @State private var isDirty: Bool = false
    @State private var isSaving: Bool = false

    /// Cached AST from the most recent parse. Lets style-only changes skip
    /// the cmark-gfm parse and re-run only the visitor.
    @State private var cachedDocument: Document?
    @State private var cachedDocumentText: String = ""
    @State private var renderVersion: Int = 0

    @State private var activeSheet: ActiveSheet?

    private var styleSignature: StyleSignature {
        StyleSignature(
            theme: settings.theme,
            fontSize: settings.fontSize,
            font: settings.font,
            justified: settings.justified,
            lineSpacing: settings.lineSpacing,
            horizontalMargin: settings.horizontalMargin
        )
    }

    enum ActiveSheet: Identifiable {
        case settings, toc, search
        var id: Int { hashValue }
    }

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()

            if let error = loadError {
                errorView(error)
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) { EmptyView() }
            ToolbarItem(placement: .topBarTrailing) {
                ModeToggleButton(theme: settings.theme, mode: mode, isDirty: isDirty) {
                    toggleMode()
                }
            }
            if mode == .editor && isDirty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveChanges()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(settings.theme.foreground)
                    }
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Menu {
                    Button("Settings", systemImage: "textformat") { activeSheet = .settings }
                    Button("Contents", systemImage: "list.bullet.indent") { activeSheet = .toc }
                    Button("Search", systemImage: "magnifyingglass") { activeSheet = .search }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(settings.theme.background, for: .bottomBar)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView(settings: settings, editorOnly: mode == .editor)
                    .presentationDetents([.medium, .large])
            case .toc:
                TableOfContentsView(
                    outline: outline,
                    theme: settings.theme,
                    onSelect: { entry in
                        if mode == .editor {
                            jumpToLine = entry.line
                        } else {
                            jumpToSectionIndex = entry.sectionIndex
                        }
                        activeSheet = nil
                    }
                )
                .presentationDetents([.medium, .large])
            case .search:
                SearchView(
                    sections: sections,
                    rawText: rawText,
                    isEditor: mode == .editor,
                    theme: settings.theme,
                    onSelectSection: { sectionIndex in
                        jumpToSectionIndex = sectionIndex
                        activeSheet = nil
                    },
                    onSelectLine: { line in
                        jumpToLine = line
                        activeSheet = nil
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear { open() }
        .onDisappear { close() }
        .onChange(of: scrollProgress) { _, newValue in
            guard mode == .reader else { return }
            recent.scrollProgress = newValue
            recent.lastOpened = Date()
            try? modelContext.save()
        }
        .onChange(of: styleSignature) { _, _ in restyle() }
        .onChange(of: rawText) { _, newValue in
            isDirty = newValue != originalText
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .tint(settings.theme.foreground)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .reader:
            MarkdownTextView(
                sections: sections,
                theme: settings.theme,
                settings: settings,
                horizontalMargin: CGFloat(settings.horizontalMargin),
                scrollProgress: $scrollProgress,
                jumpToSectionIndex: $jumpToSectionIndex,
                documentID: recent.id
            )
            // Extend the content area under the (transparent) navigation bar
            // and the home-indicator. The inner UIScrollView keeps the initial
            // content visually below the bar via its adjustedContentInset, so
            // when the user scrolls, text passes behind the bar (Apple Books).
            .ignoresSafeArea(edges: [.top, .bottom])
        case .editor:
            PlainTextEditorView(
                text: $rawText,
                jumpToLine: $jumpToLine,
                theme: settings.theme,
                fontSize: settings.editorFontSize,
                horizontalMargin: settings.editorHorizontalMargin
            )
            .ignoresSafeArea(edges: [.top, .bottom])
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Couldn't open the file")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Lifecycle

    private func open() {
        guard let resolved = recent.resolveURL() else {
            loadError = "Couldn't resolve the file bookmark."
            return
        }
        let url = resolved.url
        let started = url.startAccessingSecurityScopedResource()
        hasSecurityScope = started
        resolvedURL = url

        let needsBookmarkRefresh = resolved.isStale
        scrollProgress = recent.scrollProgress

        // Read + decode off the main thread so the navigation push stays fluid
        // even for multi-MB markdown files.
        Task.detached(priority: .userInitiated) {
            do {
                let data = try Data(contentsOf: url)
                let text = String(data: data, encoding: .utf8) ?? ""
                let document = MarkdownRenderer.parseAST(text)
                let result = MarkdownRenderer.renderSections(document: document, settings: settings)
                await MainActor.run {
                    rawText = text
                    originalText = text
                    cachedDocument = document
                    cachedDocumentText = text
                    sections = result.sections
                    outline = result.outline
                }
                if needsBookmarkRefresh,
                   let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    await MainActor.run {
                        recent.bookmarkData = fresh
                        try? modelContext.save()
                    }
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                }
            }
        }
    }

    private func close() {
        if hasSecurityScope, let url = resolvedURL {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Full parse + render. Use when the source text actually changed.
    private func rerender() {
        let snapshot = rawText
        let snapshotSettings = settings
        renderVersion &+= 1
        let v = renderVersion
        Task.detached(priority: .userInitiated) {
            let document = MarkdownRenderer.parseAST(snapshot)
            let result = MarkdownRenderer.renderSections(document: document, settings: snapshotSettings)
            await MainActor.run {
                guard v == renderVersion else { return }
                cachedDocument = document
                cachedDocumentText = snapshot
                sections = result.sections
                outline = result.outline
            }
        }
    }

    /// Style-only refresh: reuses the cached AST and only re-runs the visitor.
    /// Falls back to a full `rerender()` if the cache is missing or stale.
    private func restyle() {
        guard let document = cachedDocument, cachedDocumentText == rawText else {
            rerender()
            return
        }
        let snapshotSettings = settings
        renderVersion &+= 1
        let v = renderVersion
        Task.detached(priority: .userInitiated) {
            let result = MarkdownRenderer.renderSections(document: document, settings: snapshotSettings)
            await MainActor.run {
                guard v == renderVersion else { return }
                sections = result.sections
                outline = result.outline
            }
        }
    }

    private func toggleMode() {
        if mode == .editor && isDirty {
            saveChanges()
        }
        mode = (mode == .reader) ? .editor : .reader
        if mode == .reader {
            rerender()
        }
    }

    private func saveChanges() {
        guard let url = resolvedURL, !isSaving else { return }
        let snapshot = rawText
        isSaving = true
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        Task.detached(priority: .userInitiated) {
            do {
                try snapshot.data(using: .utf8)?.write(to: url, options: .atomic)
                await MainActor.run {
                    originalText = snapshot
                    isDirty = false
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Mode toggle button

private struct ModeToggleButton: View {
    let theme: ReaderTheme
    let mode: DocumentMode
    let isDirty: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: mode == .reader ? "pencil" : "book")
        }
    }
}

// MARK: - Table of Contents

private struct TableOfContentsView: View {
    let outline: [MarkdownOutlineEntry]
    let theme: ReaderTheme
    let onSelect: (MarkdownOutlineEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if outline.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(theme.foreground.opacity(0.5))
                        Text("This document has no headings")
                            .font(.footnote)
                            .foregroundStyle(theme.foreground.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(outline) { entry in
                        Button {
                            onSelect(entry)
                            dismiss()
                        } label: {
                            HStack {
                                Text(entry.title)
                                    .font(.system(size: 15 + (entry.level == 1 ? 1 : 0),
                                                  weight: entry.level <= 2 ? .semibold : .regular))
                                    .foregroundStyle(theme.foreground)
                                Spacer()
                            }
                            .padding(.leading, CGFloat(max(0, entry.level - 1)) * 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.background)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .background(theme.background)
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Search

private struct SearchView: View {
    let sections: [MarkdownSection]
    let rawText: String
    let isEditor: Bool
    let theme: ReaderTheme
    let onSelectSection: (Int) -> Void
    let onSelectLine: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    /// In editor mode the index is a 1-based line number; in reader mode it's a section index.
    private var hits: [(Int, String)] {
        guard query.count >= 2 else { return [] }
        let q = query.lowercased()
        if isEditor {
            return editorHits(q)
        } else {
            return readerHits(q)
        }
    }

    private func editorHits(_ q: String) -> [(Int, String)] {
        let lines = rawText.components(separatedBy: "\n")
        var out: [(Int, String)] = []
        for (i, line) in lines.enumerated() where line.lowercased().contains(q) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let snippet = trimmed.count > 160 ? String(trimmed.prefix(160)) + "…" : trimmed
            out.append((i + 1, snippet))
            if out.count >= 200 { break }
        }
        return out
    }

    private func readerHits(_ q: String) -> [(Int, String)] {
        var out: [(Int, String)] = []
        for (i, section) in sections.enumerated() {
            switch section {
            case .text(let attr), .blockquote(let attr):
                let s = attr.string
                if let range = s.range(of: q, options: .caseInsensitive) {
                    out.append((i, snippet(s, around: range)))
                }
            case .codeBlock(_, let code):
                if code.lowercased().contains(q) {
                    let trimmed = code.replacingOccurrences(of: "\n", with: " ")
                    out.append((i, String(trimmed.prefix(120)) + (trimmed.count > 120 ? "…" : "")))
                }
            case .table(let rows, _):
                let joined = rows.flatMap { $0 }.joined(separator: " ")
                if joined.lowercased().contains(q) {
                    out.append((i, "Table: " + String(joined.prefix(100))))
                }
            }
            if out.count >= 200 { break }
        }
        return out
    }

    private func snippet(_ text: String, around range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 60, limitedBy: text.endIndex) ?? text.endIndex
        var s = String(text[start..<end])
        if start != text.startIndex { s = "…" + s }
        if end != text.endIndex { s += "…" }
        return s.replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.foreground.opacity(0.55))
                    TextField("Search the document", text: $query)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(theme.foreground.opacity(0.4))
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.foreground.opacity(0.08))
                )
                .padding()

                if hits.isEmpty {
                    VStack(spacing: 8) {
                        if query.isEmpty {
                            Text("Type to search")
                        } else if query.count < 2 {
                            Text("At least 2 characters")
                        } else {
                            Text("No results")
                        }
                    }
                    .foregroundStyle(theme.foreground.opacity(0.6))
                    .font(.footnote)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(hits, id: \.0) { (index, snippet) in
                        Button {
                            if isEditor {
                                onSelectLine(index)
                            } else {
                                onSelectSection(index)
                            }
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snippet)
                                    .font(.system(size: 14))
                                    .foregroundStyle(theme.foreground)
                                    .lineLimit(2)
                                Text(isEditor ? "Line \(index)" : "Section \(index + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(theme.foreground.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.background)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .background(theme.background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
