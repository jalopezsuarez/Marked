import Foundation
import UIKit
import Markdown

/// Holds the styling helpers that turn AST inline content into NSAttributedStrings.
/// The MarkdownRenderer visitor calls these to assemble the final section content.
enum MarkdownStyles {

    // MARK: - Block helpers

    static func blockSpacer(settings: ReaderSettings) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [
            .font: settings.font.uiFont(size: CGFloat(settings.fontSize) * 0.6),
            .foregroundColor: settings.theme.uiForeground
        ])
    }

    static func paragraph(inline: NSAttributedString, settings: ReaderSettings) -> NSAttributedString {
        let p = makeParagraphStyle(settings: settings)
        let result = NSMutableAttributedString(attributedString: inline)
        result.addAttributes([.paragraphStyle: p], range: NSRange(location: 0, length: result.length))
        result.append(NSAttributedString(string: "\n"))
        return result
    }

    static func heading(inline: NSAttributedString, font: UIFont, settings: ReaderSettings) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.alignment = .natural
        p.lineSpacing = CGFloat(settings.lineSpacing) * 0.5
        p.paragraphSpacingBefore = font.lineHeight * 0.4
        p.paragraphSpacing = font.lineHeight * 0.2

        let result = NSMutableAttributedString(attributedString: inline)
        result.addAttributes([.paragraphStyle: p], range: NSRange(location: 0, length: result.length))
        result.append(NSAttributedString(string: "\n"))
        return result
    }

    /// Used as the body of a `.blockquote` section — the surrounding view
    /// supplies the indentation and visual chrome, so this just sets the
    /// paragraph metrics and word wrap.
    static func quoteBody(inline: NSAttributedString, settings: ReaderSettings) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.alignment = settings.justified ? .justified : .natural
        p.lineSpacing = CGFloat(settings.lineSpacing)
        p.paragraphSpacing = CGFloat(settings.lineSpacing) * 0.6
        p.lineBreakMode = .byWordWrapping
        p.hyphenationFactor = settings.hyphenated ? 1.0 : 0.0

        let result = NSMutableAttributedString(attributedString: inline)
        result.addAttributes([.paragraphStyle: p], range: NSRange(location: 0, length: result.length))
        return result
    }

    static func bullet(inline: NSAttributedString, settings: ReaderSettings) -> NSAttributedString {
        let font = settings.font.uiFont(size: CGFloat(settings.fontSize))
        let prefix = NSAttributedString(string: "•  ", attributes: [
            .font: font,
            .foregroundColor: settings.theme.uiForeground
        ])
        let combined = NSMutableAttributedString()
        combined.append(prefix)
        combined.append(inline)

        let p = NSMutableParagraphStyle()
        p.alignment = .natural
        p.lineSpacing = CGFloat(settings.lineSpacing)
        p.headIndent = font.pointSize * 1.3
        p.hyphenationFactor = settings.hyphenated ? 1.0 : 0.0

        combined.addAttributes([.paragraphStyle: p], range: NSRange(location: 0, length: combined.length))
        combined.append(NSAttributedString(string: "\n"))
        return combined
    }

    static func numbered(inline: NSAttributedString, n: Int, settings: ReaderSettings) -> NSAttributedString {
        let font = settings.font.uiFont(size: CGFloat(settings.fontSize))
        let prefix = NSAttributedString(string: "\(n).  ", attributes: [
            .font: font,
            .foregroundColor: settings.theme.uiForeground
        ])
        let combined = NSMutableAttributedString()
        combined.append(prefix)
        combined.append(inline)

        let p = NSMutableParagraphStyle()
        p.alignment = .natural
        p.lineSpacing = CGFloat(settings.lineSpacing)
        p.headIndent = font.pointSize * 1.6
        p.hyphenationFactor = settings.hyphenated ? 1.0 : 0.0

        combined.addAttributes([.paragraphStyle: p], range: NSRange(location: 0, length: combined.length))
        combined.append(NSAttributedString(string: "\n"))
        return combined
    }

    static func divider(settings: ReaderSettings) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        return NSAttributedString(string: "* * *\n", attributes: [
            .font: settings.font.uiFont(size: CGFloat(settings.fontSize)),
            .foregroundColor: settings.theme.uiSecondary,
            .paragraphStyle: p
        ])
    }

    // MARK: - Inline rendering (AST children → attributed string)

    static func renderInline(
        _ children: MarkupChildren,
        font: UIFont,
        color: UIColor,
        settings: ReaderSettings
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            result.append(renderInlineNode(child, font: font, color: color, settings: settings))
        }
        return result
    }

    private static func renderInlineNode(
        _ node: Markup,
        font: UIFont,
        color: UIColor,
        settings: ReaderSettings
    ) -> NSAttributedString {
        switch node {
        case let text as Markdown.Text:
            return NSAttributedString(string: text.string, attributes: [
                .font: font,
                .foregroundColor: color
            ])
        case let strong as Strong:
            let bold = applyTrait(.traitBold, to: font)
            return renderInline(strong.children, font: bold, color: color, settings: settings)
        case let emphasis as Emphasis:
            let italic = applyTrait(.traitItalic, to: font)
            return renderInline(emphasis.children, font: italic, color: color, settings: settings)
        case let strike as Strikethrough:
            let inner = renderInline(strike.children, font: font, color: color, settings: settings)
            let mutable = NSMutableAttributedString(attributedString: inner)
            mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: mutable.length))
            return mutable
        case let code as InlineCode:
            let mono = UIFont.monospacedSystemFont(ofSize: max(8, font.pointSize - 4), weight: .regular)
            // U+2009 thin space provides pill-style padding around the highlight.
            return NSAttributedString(string: "\u{2009}" + code.code + "\u{2009}", attributes: [
                .font: mono,
                .foregroundColor: settings.theme.codeForeground,
                .backgroundColor: settings.theme.inlineCodeBackground
            ])
        case let link as Markdown.Link:
            let inner = renderInline(link.children, font: font, color: color, settings: settings)
            let mutable = NSMutableAttributedString(attributedString: inner)
            let linkColor: UIColor = settings.theme == .dark ? .systemTeal : .systemBlue
            mutable.addAttributes([
                .foregroundColor: linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: NSRange(location: 0, length: mutable.length))
            if let dest = link.destination, let url = URL(string: dest) {
                mutable.addAttribute(.link, value: url, range: NSRange(location: 0, length: mutable.length))
            }
            return mutable
        case let image as Markdown.Image:
            let label = image.plainText.isEmpty ? (image.title ?? "image") : image.plainText
            return NSAttributedString(string: "🖼️ \(label)", attributes: [
                .font: font,
                .foregroundColor: settings.theme.uiSecondary
            ])
        case _ as LineBreak, _ as SoftBreak:
            return NSAttributedString(string: " ", attributes: [.font: font, .foregroundColor: color])
        case let html as InlineHTML:
            return NSAttributedString(string: html.rawHTML, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: max(8, font.pointSize - 4), weight: .regular),
                .foregroundColor: settings.theme.uiSecondary
            ])
        default:
            return NSAttributedString(string: node.format(), attributes: [.font: font, .foregroundColor: color])
        }
    }

    private static func applyTrait(_ trait: UIFontDescriptor.SymbolicTraits, to font: UIFont) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(trait)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        }
        return font
    }

    private static func makeParagraphStyle(settings: ReaderSettings) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = settings.justified ? .justified : .natural
        p.lineSpacing = CGFloat(settings.lineSpacing)
        p.lineBreakMode = .byWordWrapping
        p.hyphenationFactor = settings.hyphenated ? 1.0 : 0.0
        return p
    }
}
