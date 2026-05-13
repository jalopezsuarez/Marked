import Foundation
import UIKit
import Markdown

enum MarkdownSection: Equatable {
    case text(NSAttributedString)
    case codeBlock(language: String?, code: String)
    case table(rows: [[String]], alignments: [ColumnAlignment])
    case blockquote(NSAttributedString)

    enum ColumnAlignment: String, Equatable {
        case left, center, right
    }

    static func == (lhs: MarkdownSection, rhs: MarkdownSection) -> Bool {
        switch (lhs, rhs) {
        case (.text(let l), .text(let r)):
            return l.isEqual(to: r)
        case (.codeBlock(let ll, let lc), .codeBlock(let rl, let rc)):
            return ll == rl && lc == rc
        case (.table(let lr, let la), .table(let rr, let ra)):
            return lr == rr && la == ra
        case (.blockquote(let l), .blockquote(let r)):
            return l.isEqual(to: r)
        default:
            return false
        }
    }
}

/// Outline entry produced alongside section parsing for the TOC view.
struct MarkdownOutlineEntry: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let level: Int
    /// Index into the `[MarkdownSection]` array — used by the reader to scroll.
    let sectionIndex: Int
    /// 1-based source line of the heading — used by the editor to scroll.
    let line: Int
}

/// Result of a parse pass: section list + table-of-contents entries.
struct MarkdownParseResult: Equatable {
    var sections: [MarkdownSection]
    var outline: [MarkdownOutlineEntry]
}

/// Parses markdown via swift-markdown (cmark-gfm) and turns the AST into
/// a flat `[MarkdownSection]` ready to be rendered by the container view.
enum MarkdownRenderer {
    /// Phase 1: source → AST. Expensive; cache and reuse when only style changes.
    static func parseAST(_ markdown: String) -> Document {
        Document(parsing: markdown, options: [.parseBlockDirectives])
    }

    /// Phase 2: AST → styled sections + outline. Re-runs cheaply when settings change.
    static func renderSections(document: Document, settings: ReaderSettings) -> MarkdownParseResult {
        var visitor = SectionVisitor(settings: settings)
        visitor.visit(document)
        return MarkdownParseResult(sections: visitor.finish(), outline: visitor.outline)
    }

    /// Convenience: full parse + render in one call.
    static func parse(_ markdown: String, settings: ReaderSettings) -> MarkdownParseResult {
        renderSections(document: parseAST(markdown), settings: settings)
    }
}

// MARK: - AST → sections visitor

private struct SectionVisitor: MarkupWalker {
    let settings: ReaderSettings

    private var sections: [MarkdownSection] = []
    private var current = NSMutableAttributedString()
    private var currentIsEmpty = true
    var outline: [MarkdownOutlineEntry] = []

    init(settings: ReaderSettings) {
        self.settings = settings
    }

    mutating func finish() -> [MarkdownSection] {
        flush()
        return sections
    }

    private mutating func flush() {
        if current.length > 0 {
            sections.append(.text(current.copy() as! NSAttributedString))
            current = NSMutableAttributedString()
        }
        currentIsEmpty = true
    }

    private mutating func appendBlock(_ piece: NSAttributedString) {
        if !currentIsEmpty {
            current.append(MarkdownStyles.blockSpacer(settings: settings))
        }
        current.append(piece)
        currentIsEmpty = false
    }

    // MARK: Walker overrides

    mutating func visitDocument(_ document: Document) {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let inline = MarkdownStyles.renderInline(
            paragraph.children,
            font: settings.font.uiFont(size: CGFloat(settings.fontSize)),
            color: settings.theme.uiForeground,
            settings: settings
        )
        appendBlock(MarkdownStyles.paragraph(inline: inline, settings: settings))
    }

    mutating func visitHeading(_ heading: Heading) {
        // Close any in-progress text section so this heading begins its own —
        // that's what makes TOC jumps land on the heading itself, not on the
        // start of the surrounding paragraph block.
        flush()

        let level = Swift.min(Swift.max(1, heading.level), 6)
        let scale: CGFloat
        switch level {
        case 1: scale = 1.9
        case 2: scale = 1.55
        case 3: scale = 1.3
        default: scale = 1.15
        }
        let font = settings.font.uiFont(size: CGFloat(settings.fontSize) * scale, weight: .bold)
        let inline = MarkdownStyles.renderInline(
            heading.children,
            font: font,
            color: settings.theme.uiForeground,
            settings: settings
        )

        let upcomingIndex = sections.count
        let line = heading.range?.lowerBound.line ?? 1
        outline.append(MarkdownOutlineEntry(
            title: heading.plainText,
            level: level,
            sectionIndex: upcomingIndex,
            line: line
        ))

        appendBlock(MarkdownStyles.heading(inline: inline, font: font, settings: settings))
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        flush()
        let combined = NSMutableAttributedString()
        var first = true
        for child in blockQuote.children {
            if !first { combined.append(NSAttributedString(string: "\n")) }
            first = false
            if let para = child as? Paragraph {
                let inline = MarkdownStyles.renderInline(
                    para.children,
                    font: settings.font.uiFont(size: CGFloat(settings.fontSize), italic: true),
                    color: settings.theme.uiSecondary,
                    settings: settings
                )
                combined.append(inline)
            } else {
                combined.append(NSAttributedString(string: child.format()))
            }
        }
        sections.append(.blockquote(MarkdownStyles.quoteBody(inline: combined, settings: settings)))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        flush()
        sections.append(.codeBlock(language: codeBlock.language, code: codeBlock.code.trimmingCharacters(in: .newlines)))
    }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        let combined = NSMutableAttributedString()
        for case let item as ListItem in list.children {
            let inline = inlineForListItem(item)
            combined.append(MarkdownStyles.bullet(inline: inline, settings: settings))
        }
        appendBlock(combined)
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        let combined = NSMutableAttributedString()
        var n = Int(list.startIndex)
        for case let item as ListItem in list.children {
            let inline = inlineForListItem(item)
            combined.append(MarkdownStyles.numbered(inline: inline, n: n, settings: settings))
            n += 1
        }
        appendBlock(combined)
    }

    private func inlineForListItem(_ item: ListItem) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in item.children {
            if let para = child as? Paragraph {
                let inline = MarkdownStyles.renderInline(
                    para.children,
                    font: settings.font.uiFont(size: CGFloat(settings.fontSize)),
                    color: settings.theme.uiForeground,
                    settings: settings
                )
                if result.length > 0 { result.append(NSAttributedString(string: " ")) }
                result.append(inline)
            }
        }
        return result
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        appendBlock(MarkdownStyles.divider(settings: settings))
    }

    mutating func visitTable(_ table: Markdown.Table) {
        flush()
        var rows: [[String]] = []
        var alignments: [MarkdownSection.ColumnAlignment] = []

        // Header row + alignments
        let head = table.head
        var headRow: [String] = []
        for case let cell as Markdown.Table.Cell in head.children {
            headRow.append(cell.plainText)
        }
        rows.append(headRow)

        for col in table.columnAlignments {
            switch col {
            case .left?:    alignments.append(.left)
            case .right?:   alignments.append(.right)
            case .center?:  alignments.append(.center)
            case nil:       alignments.append(.left)
            }
        }
        // pad alignment array
        while alignments.count < headRow.count { alignments.append(.left) }

        // Body rows
        let body = table.body
        for case let row as Markdown.Table.Row in body.children {
            var cells: [String] = []
            for case let cell as Markdown.Table.Cell in row.children {
                cells.append(cell.plainText)
            }
            rows.append(cells)
        }

        sections.append(.table(rows: rows, alignments: alignments))
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        // Render raw HTML as a code block — better than dropping content.
        flush()
        sections.append(.codeBlock(language: "html", code: html.rawHTML))
    }
}
