import SwiftUI

/// Settings sheet — edits a local snapshot and only commits to ReaderSettings.shared
/// when the user taps "Apply". This keeps the live document fully responsive while
/// dragging sliders.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: ReaderSettings
    var editorOnly: Bool = false

    // Local draft — edited freely, committed by tapping "Apply".
    @State private var draftFontSize: Double = 18
    @State private var draftLineSpacing: Double = 6
    @State private var draftHorizontalMargin: Double = 22
    @State private var draftFont: ReaderFont = .system
    @State private var draftJustified: Bool = true
    @State private var draftTheme: ReaderTheme = .light
    @State private var draftEditorFontSize: Double = 15
    @State private var draftEditorHorizontalMargin: Double = 16
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                if editorOnly {
                    editorSections
                } else {
                    readerSections
                }
            }
            .navigationTitle(editorOnly ? "Editor settings" : "Reader settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { commit() }
                        .fontWeight(.semibold)
                        .disabled(!isDirty)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loadDraft()
            loaded = true
        }
    }

    private var isDirty: Bool {
        if editorOnly {
            return settings.editorFontSize != draftEditorFontSize
                || settings.editorHorizontalMargin != draftEditorHorizontalMargin
                || settings.theme != draftTheme
        }
        return settings.fontSize != draftFontSize
            || settings.lineSpacing != draftLineSpacing
            || settings.horizontalMargin != draftHorizontalMargin
            || settings.font != draftFont
            || settings.justified != draftJustified
            || settings.theme != draftTheme
    }

    private func loadDraft() {
        draftFontSize = settings.fontSize
        draftLineSpacing = settings.lineSpacing
        draftHorizontalMargin = settings.horizontalMargin
        draftFont = settings.font
        draftJustified = settings.justified
        draftTheme = settings.theme
        draftEditorFontSize = settings.editorFontSize
        draftEditorHorizontalMargin = settings.editorHorizontalMargin
    }

    private func commit() {
        if editorOnly {
            if settings.editorFontSize != draftEditorFontSize {
                settings.editorFontSize = draftEditorFontSize
            }
            if settings.editorHorizontalMargin != draftEditorHorizontalMargin {
                settings.editorHorizontalMargin = draftEditorHorizontalMargin
            }
            if settings.theme != draftTheme { settings.theme = draftTheme }
        } else {
            if settings.fontSize != draftFontSize { settings.fontSize = draftFontSize }
            if settings.lineSpacing != draftLineSpacing { settings.lineSpacing = draftLineSpacing }
            if settings.horizontalMargin != draftHorizontalMargin { settings.horizontalMargin = draftHorizontalMargin }
            if settings.font != draftFont { settings.font = draftFont }
            if settings.justified != draftJustified { settings.justified = draftJustified }
            if settings.theme != draftTheme { settings.theme = draftTheme }
        }
    }

    @ViewBuilder
    private var editorSections: some View {
        Section("Size") {
            HStack {
                Image(systemName: "textformat.size.smaller")
                Slider(value: $draftEditorFontSize, in: 10...28, step: 1)
                Image(systemName: "textformat.size.larger")
            }
            Text("\(Int(draftEditorFontSize)) pt · monospaced")
                .font(.system(size: draftEditorFontSize, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        }

        Section("Theme") {
            Picker("Theme", selection: $draftTheme) {
                ForEach(ReaderTheme.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
        }

        Section("Side margins") {
            HStack {
                Image(systemName: "rectangle.compress.vertical")
                    .rotationEffect(.degrees(90))
                Slider(value: $draftEditorHorizontalMargin, in: 4...48, step: 1)
                Image(systemName: "rectangle.expand.vertical")
                    .rotationEffect(.degrees(90))
            }
            Text("\(Int(draftEditorHorizontalMargin)) pt")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
    }

    @ViewBuilder
    private var readerSections: some View {
        Section("Size") {
            HStack {
                Image(systemName: "textformat.size.smaller")
                Slider(value: $draftFontSize, in: 12...32, step: 1)
                Image(systemName: "textformat.size.larger")
            }
            Text("Aa  \(Int(draftFontSize)) pt")
                .font(.system(size: draftFontSize))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        }

        Section("Theme") {
            Picker("Theme", selection: $draftTheme) {
                ForEach(ReaderTheme.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
        }

        Section("Line spacing") {
            Slider(value: $draftLineSpacing, in: 0...14, step: 1)
            Text("\(Int(draftLineSpacing)) pt")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }

        Section("Side margins") {
            HStack {
                Image(systemName: "rectangle.compress.vertical")
                    .rotationEffect(.degrees(90))
                Slider(value: $draftHorizontalMargin, in: 8...64, step: 1)
                Image(systemName: "rectangle.expand.vertical")
                    .rotationEffect(.degrees(90))
            }
            Text("\(Int(draftHorizontalMargin)) pt")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }

        Section("Font") {
            Picker("Font", selection: $draftFont) {
                ForEach(ReaderFont.allCases) { f in
                    Text(f.displayName)
                        .font(.custom(swiftUIFontName(f), size: 17))
                        .tag(f)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Section {
            Toggle("Justified text", isOn: $draftJustified)
        } header: {
            Text("Composition")
        } footer: {
            Text("Hyphenation is applied automatically when text is justified.")
        }
    }

    private func swiftUIFontName(_ f: ReaderFont) -> String {
        switch f {
        case .system:        return "-apple-system"
        case .newYork:       return "NewYork-Regular"
        case .georgia:       return "Georgia"
        case .palatino:      return "Palatino-Roman"
        case .timesNewRoman: return "TimesNewRomanPSMT"
        case .helvetica:     return "HelveticaNeue"
        case .avenirNext:    return "AvenirNext-Regular"
        case .iowanOldStyle: return "IowanOldStyle-Roman"
        case .charter:       return "Charter-Roman"
        }
    }
}
