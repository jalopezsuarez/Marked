# Marked

A SwiftUI markdown reader and editor for iOS, designed as a reading-first app — think Apple Books for `.md` files: careful typography, reading themes, per-document progress and a built-in plain-text editor for quick edits.

Marketing site: [jalopezsuarez.github.io/Marked](https://jalopezsuarez.github.io/Marked/) (served from the [`docs/`](docs/) folder via GitHub Pages).

## Features

- **Reader mode** with native rendering (headings, lists, tables, code blocks, quotes, links…).
- **Editor mode** with plain-text editing and in-place saving to the original file. New documents open straight into the editor.
- **Syntax highlighting** for fenced code blocks (auto-detected language) and live markdown markup colouring in the editor, powered by [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) (highlight.js).
- **Styled blockquotes** with left accent bar, faint background tint and a decorative quote glyph.
- **Wrap-first tables** that fit cell text to the available width, falling back to horizontal scroll only when even wrapping cannot make the table fit.
- **Reading themes**: light, sepia and dark, with theme-aware backgrounds for fenced code blocks, tables and blockquotes so syntax highlighting stays legible in every mode. The theme picker is reachable from both the reader and editor settings sheets.
- **Curated typefaces**: system serif, New York, Georgia, Palatino, Times New Roman, Helvetica Neue, Avenir Next, Iowan Old Style and Charter.
- **Composition**: font size, line spacing, horizontal margins and justified text with automatic hyphenation.
- **Recent files** persisted with SwiftData and security-scoped bookmarks — they remember location and reading progress per document. The list shows the total file count under the title (Apple Notes–style) and self-heals on launch, on returning from a document and on app foreground: missing files are pruned, renames are picked up, and pull-to-refresh re-runs the same sweep on demand.
- Auto-generated **table of contents** and in-document **search** (per section in reader mode, per line in editor mode).
- Open from the system (Files, iCloud Drive, "Open with…") and create new documents via the exporter.
- Document association with the standard Markdown UTIs (`md`, `markdown`, `mdown`, `mkd`).
- **Performance**: documents open asynchronously, theme and font swaps reuse the parsed AST and existing section views instead of rebuilding, and the editor debounces highlighting so large files stay responsive while typing.

## Project structure

```
Marked/
├── Marked.xcodeproj
├── Info.plist
├── Marked/                     App source
│   ├── MarkedApp.swift         SwiftUI entry point + ModelContainer
│   ├── ContentView.swift       Recents list
│   ├── DocumentView.swift      Reader/editor with TOC and search
│   ├── MarkdownDocument.swift  FileDocument for creating/exporting .md
│   ├── MarkdownRenderer.swift  Parser to renderable sections
│   ├── MarkdownTextView.swift  UIScrollView-based renderer (uses HighlighterSwift for code blocks and the live editor)
│   ├── MarkdownStyles.swift    Typographic styles
│   ├── ReaderSettings.swift    Theme, font, margins (UserDefaults)
│   ├── RecentFile.swift        SwiftData model + bookmark
│   └── SettingsView.swift      Settings sheet (reader / editor)
├── MarkedTests/
└── MarkedUITests/
```

## Requirements

- Xcode 26 or later
- iOS 26 or later
- Swift 5.9+

## Dependencies

Resolved automatically through Swift Package Manager — no manual setup required:

- [swift-markdown](https://github.com/swiftlang/swift-markdown) — CommonMark / GFM parser.
- [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) — highlight.js bridge for syntax highlighting in code blocks and the live editor.

## Build and run

1. Open `Marked/Marked.xcodeproj` in Xcode.
2. Pick the **Marked** target and a simulator or device.
3. Hit `⌘R` to build and run.

## Usage

- The main list shows **Marked** with a live count of recent files underneath, Apple Notes–style.
- Tap the **folder** icon to open a `.md` from Files or iCloud, or **pencil** to create a new one.
- Inside a document, the bottom-right **`…` menu** in the toolbar gives access to **Settings**, **Table of Contents** and **Search**.
- The top-right icon toggles between **reader** (book) and **editor** (pencil). In editor mode a check button appears to save changes.
- Reading progress is saved automatically as you scroll.

## Privacy

Marked runs entirely on your device. No servers, no data collection, no network connections. The full policy is published at [jalopezsuarez.github.io/Marked/privacy.html](https://jalopezsuarez.github.io/Marked/privacy.html) (source: [`docs/privacy.md`](docs/privacy.md)); `Marked/Marked/PrivacyInfo.xcprivacy` carries the technical declaration.

## Author

Jose Antonio Lopez — [@jalopezsuarez](https://github.com/jalopezsuarez) · `jalopezsuarez@gmail.com`

## License

[MIT](LICENSE) © 2026 Vemovi.
