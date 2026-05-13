import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \RecentFile.lastOpened, order: .reverse) private var recents: [RecentFile]

    @State private var showImporter = false
    @State private var showCreateExporter = false
    @State private var pendingDocument = MarkdownDocument(text: "")
    @State private var openTarget: RecentFile?
    @State private var importError: String?
    @State private var nextOpenMode: DocumentMode = .reader

    private var settings = ReaderSettings.shared

    var body: some View {
        NavigationStack {
            rootContent
                .navigationTitle("Marked")
                .navigationSubtitle(countSubtitle)
                .toolbar { topToolbar }
                .navigationDestination(item: $openTarget) { file in
                    DocumentView(recent: file, initialMode: nextOpenMode)
                }
                .modifier(FilePickerModifiers(
                    showImporter: $showImporter,
                    showCreateExporter: $showCreateExporter,
                    pendingDocument: $pendingDocument,
                    importError: $importError,
                    importableTypes: importableTypes,
                    onImport: handleImport,
                    onCreate: handleCreate
                ))
                .preferredColorScheme(settings.theme.colorScheme)
                .toolbarBackground(settings.theme.background, for: .navigationBar)
                .tint(settings.theme.foreground)
                .onOpenURL { url in
                    nextOpenMode = .reader
                    registerFile(at: url)
                }
                .onAppear {
                    Task { await refreshFiles() }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await refreshFiles() }
                    }
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()

            if recents.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                pendingDocument = MarkdownDocument(text: "# Untitled\n\n")
                showCreateExporter = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showImporter = true
            } label: {
                Image(systemName: "folder")
            }
        }
    }

    private var fileList: some View {
        List {
            ForEach(recents) { file in
                Button {
                    nextOpenMode = .reader
                    openTarget = file
                } label: {
                    RecentRow(file: file, theme: settings.theme)
                }
                .listRowBackground(settings.theme.background)
                .foregroundStyle(settings.theme.foreground)
            }
            .onDelete(perform: deleteFiles)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .refreshable { await refreshFiles() }
    }

    private var countSubtitle: String {
        switch recents.count {
        case 0: return "No markdown files"
        case 1: return "1 markdown file"
        default: return "\(recents.count) markdown files"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "book.pages")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(settings.theme.foreground.opacity(0.6))
            Text("No recent files")
                .font(.title3)
                .foregroundStyle(settings.theme.foreground)
            Text("Open a .md to start reading.\nMarked will remember where you left off in each one.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(settings.theme.foreground.opacity(0.7))
            Button {
                showImporter = true
            } label: {
                Label("Open file", systemImage: "folder")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(settings.theme.foreground.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.top, 4)
        }
        .padding()
    }


    private var importableTypes: [UTType] {
        var list: [UTType] = []
        if let md = UTType(filenameExtension: "md") { list.append(md) }
        if let mdown = UTType(filenameExtension: "markdown") { list.append(mdown) }
        list.append(.plainText)
        list.append(.text)
        return list
    }

    // MARK: - Importer

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            nextOpenMode = .reader
            registerFile(at: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func registerFile(at url: URL) {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let path = url.path
            let displayPath = humanReadablePath(for: url)

            if let existing = matchExistingRecent(for: url) {
                existing.lastOpened = Date()
                existing.bookmarkData = bookmark
                if existing.displayPath != displayPath { existing.displayPath = displayPath }
                if existing.resolvedPath != path { existing.resolvedPath = path }
                try? modelContext.save()
                openTarget = existing
                return
            }

            let file = RecentFile(
                name: url.lastPathComponent,
                bookmarkData: bookmark,
                displayPath: displayPath,
                resolvedPath: path
            )
            modelContext.insert(file)
            try? modelContext.save()
            openTarget = file
        } catch {
            importError = error.localizedDescription
        }
    }

    private func humanReadablePath(for url: URL) -> String {
        var path = url.deletingLastPathComponent().path
        if let r = path.range(of: "com~apple~CloudDocs") {
            path = "iCloud Drive" + path[r.upperBound...]
        } else if let r = path.range(of: "/File Provider Storage") {
            path = "iCloud" + String(path[r.upperBound...])
        } else {
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                path = "~" + path.dropFirst(home.count)
            }
        }
        return path
    }

    private func matchExistingRecent(for url: URL) -> RecentFile? {
        let target = url.path
        // Fast path: cached resolved path.
        if let hit = recents.first(where: { !$0.resolvedPath.isEmpty && $0.resolvedPath == target }) {
            return hit
        }
        // Fallback: resolve bookmarks (only for legacy records without a cached path).
        for recent in recents where recent.resolvedPath.isEmpty {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: recent.bookmarkData, bookmarkDataIsStale: &stale),
               resolved.path == target {
                recent.resolvedPath = target
                return recent
            }
        }
        return nil
    }

    private func handleCreate(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            nextOpenMode = .editor
            registerFile(at: url)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func deleteFiles(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(recents[index])
        }
        try? modelContext.save()
    }

    @MainActor
    private func refreshFiles() async {
        for file in recents {
            guard let resolved = file.resolveURL() else {
                modelContext.delete(file)
                continue
            }
            let url = resolved.url
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }

            guard FileManager.default.fileExists(atPath: url.path) else {
                modelContext.delete(file)
                continue
            }

            let currentName = url.lastPathComponent
            if file.name != currentName { file.name = currentName }

            let currentDisplay = humanReadablePath(for: url)
            if file.displayPath != currentDisplay { file.displayPath = currentDisplay }

            if file.resolvedPath != url.path { file.resolvedPath = url.path }

            if resolved.isStale,
               let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                file.bookmarkData = fresh
            }
        }
        try? modelContext.save()
    }
}

private struct FilePickerModifiers: ViewModifier {
    @Binding var showImporter: Bool
    @Binding var showCreateExporter: Bool
    @Binding var pendingDocument: MarkdownDocument
    @Binding var importError: String?
    let importableTypes: [UTType]
    let onImport: (Result<[URL], Error>) -> Void
    let onCreate: (Result<URL, Error>) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importableTypes,
                allowsMultipleSelection: false,
                onCompletion: onImport
            )
            .fileExporter(
                isPresented: $showCreateExporter,
                document: pendingDocument,
                contentType: UTType(filenameExtension: "md") ?? .plainText,
                defaultFilename: "Untitled",
                onCompletion: onCreate
            )
            .alert("Couldn't open", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
    }
}

private struct RecentRow: View {
    @Bindable var file: RecentFile
    let theme: ReaderTheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 22))
                .foregroundStyle(theme.foreground.opacity(0.7))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.foreground)
                if !file.displayPath.isEmpty {
                    Text(file.displayPath)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(theme.foreground.opacity(0.55))
                }
                HStack(spacing: 8) {
                    Text(file.lastOpened, format: .relative(presentation: .named))
                    if file.scrollProgress > 0.005 {
                        Text("·")
                        Text("\(Int((file.scrollProgress * 100).rounded()))%")
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.foreground.opacity(0.6))
            }
            Spacer()
            ProgressGauge(progress: file.scrollProgress, color: theme.foreground)
                .frame(width: 22, height: 22)
        }
        .padding(.vertical, 6)
    }
}

private struct ProgressGauge: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
