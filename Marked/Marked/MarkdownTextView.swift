import SwiftUI
import UIKit
import Highlighter

struct MarkdownTextView: UIViewRepresentable {
    let sections: [MarkdownSection]
    let theme: ReaderTheme
    let settings: ReaderSettings
    let horizontalMargin: CGFloat
    @Binding var scrollProgress: Double
    @Binding var jumpToSectionIndex: Int?
    let documentID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollProgress: $scrollProgress, jumpToSectionIndex: $jumpToSectionIndex)
    }

    func makeUIView(context: Context) -> MarkdownContainerView {
        let v = MarkdownContainerView()
        v.scrollView.delegate = context.coordinator
        v.alpha = 0
        return v
    }

    func updateUIView(_ container: MarkdownContainerView, context: Context) {
        container.backgroundColor = theme.uiBackground

        guard !sections.isEmpty else { return }

        let isNewDocument = context.coordinator.currentDocumentID != documentID
        let contentChanged = !context.coordinator.matchesSections(sections)
        let marginChanged = abs(container.horizontalMargin - horizontalMargin) > 0.5
        let themeChanged = container.theme != theme
        let settingsChanged = container.settings.fontSize != settings.fontSize
            || container.settings.font != settings.font
            || container.settings.lineSpacing != settings.lineSpacing
            || container.settings.justified != settings.justified

        if isNewDocument || !context.coordinator.contentApplied {
            context.coordinator.suspendsScrollTracking = true
            container.setSections(sections, settings: settings, theme: theme, horizontalMargin: horizontalMargin)
            context.coordinator.contentApplied = true
            context.coordinator.currentDocumentID = documentID
            context.coordinator.lastSections = sections
            context.coordinator.pendingProgress = scrollProgress
            context.coordinator.scheduleScrollRestoration(container: container)
        } else if contentChanged || marginChanged || themeChanged || settingsChanged {
            let progress = currentProgress(of: container.scrollView)
            context.coordinator.suspendsScrollTracking = true
            container.setSections(sections, settings: settings, theme: theme, horizontalMargin: horizontalMargin)
            context.coordinator.lastSections = sections
            context.coordinator.pendingProgress = progress
            context.coordinator.scheduleScrollRestoration(container: container)
        }

        // Programmatic jump from TOC / search.
        if let target = jumpToSectionIndex, target < container.stackView.arrangedSubviews.count {
            DispatchQueue.main.async {
                jumpToSectionIndex = nil
            }
            context.coordinator.scrollTo(sectionIndex: target, in: container)
        }
    }

    private func currentProgress(of sv: UIScrollView) -> Double {
        let scrollable = sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.top + sv.adjustedContentInset.bottom
        guard scrollable > 0 else { return 0 }
        let y = sv.contentOffset.y + sv.adjustedContentInset.top
        return Double(Swift.min(scrollable, Swift.max(0, y)) / scrollable)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var scrollProgress: Double
        @Binding var jumpToSectionIndex: Int?
        var currentDocumentID: UUID?
        var contentApplied: Bool = false
        var suspendsScrollTracking: Bool = false
        var pendingProgress: Double = 0
        var lastSections: [MarkdownSection] = []
        private var restoreAttempts = 0

        init(scrollProgress: Binding<Double>, jumpToSectionIndex: Binding<Int?>) {
            _scrollProgress = scrollProgress
            _jumpToSectionIndex = jumpToSectionIndex
        }

        func matchesSections(_ s: [MarkdownSection]) -> Bool {
            s == lastSections
        }

        // MARK: - Programmatic jump

        func scrollTo(sectionIndex: Int, in container: MarkdownContainerView) {
            DispatchQueue.main.async { [weak container] in
                guard let container,
                      sectionIndex < container.stackView.arrangedSubviews.count else { return }
                container.layoutIfNeeded()
                let view = container.stackView.arrangedSubviews[sectionIndex]
                let frameInScroll = view.convert(view.bounds, to: container.scrollView)
                let targetY = frameInScroll.minY - container.scrollView.adjustedContentInset.top - 8
                container.scrollView.setContentOffset(
                    CGPoint(x: 0, y: max(-container.scrollView.adjustedContentInset.top, targetY)),
                    animated: true
                )
            }
        }

        // MARK: - Restore

        func scheduleScrollRestoration(container: MarkdownContainerView) {
            restoreAttempts = 0
            attemptScrollRestoration(container: container)
        }

        private func attemptScrollRestoration(container: MarkdownContainerView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak container] in
                guard let self, let container else { return }
                container.layoutIfNeeded()
                let sv = container.scrollView
                // Same formula as save: total scrollable height including both insets.
                let scrollable = sv.contentSize.height + sv.adjustedContentInset.top + sv.adjustedContentInset.bottom - sv.bounds.height
                var scrolled = false

                if scrollable > 0 {
                    let y = CGFloat(self.pendingProgress) * scrollable - sv.adjustedContentInset.top
                    sv.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                    scrolled = true
                }

                // Retry while the layout hasn't produced a content size yet. We retry
                // even when pendingProgress is 0 because we still need to wait for layout
                // before unhiding the view (otherwise the fade-in shows an empty container).
                if !scrolled, self.restoreAttempts < 12 {
                    self.restoreAttempts += 1
                    self.attemptScrollRestoration(container: container)
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    self.suspendsScrollTracking = false
                    if container.alpha < 1 {
                        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
                            container.alpha = 1
                        }
                    }
                }
            }
        }

        // MARK: - Scroll tracking
        //
        // We deliberately DO NOT update `scrollProgress` on every scroll event:
        // phantom layout-driven scrolls that fire during view tear-down would
        // otherwise overwrite the saved position with 0. Instead, we commit only
        // when the user actually finishes scrolling.

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { commitProgress(scrollView) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            commitProgress(scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            commitProgress(scrollView)
        }

        private func commitProgress(_ scrollView: UIScrollView) {
            guard !suspendsScrollTracking else { return }
            let scrollable = scrollView.contentSize.height - scrollView.bounds.height
                + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom
            // Refuse to commit when the layout isn't real yet — protects the
            // saved position against transient scroll events while the document
            // is loading or the navigation stack is being torn down.
            guard scrollable > 0 else { return }
            let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            let progress = Double(Swift.min(scrollable, Swift.max(0, y)) / scrollable)
            if abs(progress - scrollProgress) > 0.001 {
                scrollProgress = progress
            }
        }
    }
}

// MARK: - Container

final class MarkdownContainerView: UIView {
    let scrollView = UIScrollView()
    let stackView = UIStackView()
    private(set) var horizontalMargin: CGFloat = 22
    private(set) var theme: ReaderTheme = .light
    private(set) var settings: ReaderSettings = ReaderSettings.shared

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .automatic

        scrollView.addSubview(stackView)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .equalSpacing
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -80),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    func setSections(_ sections: [MarkdownSection], settings: ReaderSettings, theme: ReaderTheme, horizontalMargin: CGFloat) {
        self.settings = settings
        self.theme = theme
        self.horizontalMargin = horizontalMargin
        backgroundColor = theme.uiBackground
        scrollView.backgroundColor = theme.uiBackground

        // Diff against the current arranged subviews. When the section at an
        // index has the same kind as the existing view, mutate it in place
        // (theme/font swaps just reassign `attributedText`); otherwise rebuild.
        let arranged = stackView.arrangedSubviews
        for (i, section) in sections.enumerated() {
            if i < arranged.count, let reused = updateInPlace(arranged[i], with: section, settings: settings, theme: theme, horizontalMargin: horizontalMargin) {
                _ = reused
            } else {
                if i < arranged.count {
                    let old = arranged[i]
                    stackView.removeArrangedSubview(old)
                    old.removeFromSuperview()
                }
                let view = makeSectionView(section, settings: settings, theme: theme, horizontalMargin: horizontalMargin)
                stackView.insertArrangedSubview(view, at: i)
            }
        }
        // Drop trailing views when the new list is shorter.
        while stackView.arrangedSubviews.count > sections.count {
            let last = stackView.arrangedSubviews[sections.count]
            stackView.removeArrangedSubview(last)
            last.removeFromSuperview()
        }
    }

    private func updateInPlace(_ view: UIView, with section: MarkdownSection, settings: ReaderSettings, theme: ReaderTheme, horizontalMargin: CGFloat) -> UIView? {
        switch section {
        case .text(let attr):
            guard let v = view as? TextSectionView else { return nil }
            v.update(attr: attr, theme: theme, horizontalMargin: horizontalMargin)
            return v
        case .codeBlock(let language, let code):
            guard let v = view as? CodeSectionView else { return nil }
            v.update(language: language, raw: code, settings: settings, theme: theme, horizontalMargin: horizontalMargin)
            return v
        case .blockquote(let attr):
            guard let v = view as? QuoteSectionView else { return nil }
            v.update(attr: attr, theme: theme, horizontalMargin: horizontalMargin)
            return v
        case .table:
            // Tables hold internal layout state; cheaper to rebuild than reset.
            return nil
        }
    }

    private func makeSectionView(_ section: MarkdownSection, settings: ReaderSettings, theme: ReaderTheme, horizontalMargin: CGFloat) -> UIView {
        switch section {
        case .text(let attr):
            return TextSectionView(attr: attr, theme: theme, horizontalMargin: horizontalMargin)
        case .codeBlock(let language, let code):
            return CodeSectionView(language: language, raw: code, settings: settings, theme: theme, horizontalMargin: horizontalMargin)
        case .table(let rows, let alignments):
            return makeTableSectionView(rows: rows, alignments: alignments, settings: settings, theme: theme, horizontalMargin: horizontalMargin)
        case .blockquote(let attr):
            return QuoteSectionView(attr: attr, theme: theme, horizontalMargin: horizontalMargin)
        }
    }


    private func makeTableSectionView(rows: [[String]], alignments: [MarkdownSection.ColumnAlignment], settings: ReaderSettings, theme: ReaderTheme, horizontalMargin: CGFloat) -> UIView {
        let outer = UIView()
        outer.translatesAutoresizingMaskIntoConstraints = false

        // Card with rounded corners and a thin border (GitHub-style).
        let card = UIView()
        card.backgroundColor = theme.codeBackground
        card.layer.cornerRadius = 6
        card.layer.borderWidth = 1
        card.layer.borderColor = theme.tableBorderColor.cgColor
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(card)

        let tableFontSize = max(8, CGFloat(settings.fontSize) - 4)
        let bodyFont = settings.font.uiFont(size: tableFontSize)
        let headerFont = settings.font.uiFont(size: tableFontSize, weight: .semibold)

        let table = WrappingTableView(
            rows: rows,
            alignments: alignments,
            headerFont: headerFont,
            bodyFont: bodyFont,
            theme: theme
        )
        table.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(table)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: outer.topAnchor),
            card.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: outer.leadingAnchor, constant: horizontalMargin),
            card.trailingAnchor.constraint(equalTo: outer.trailingAnchor, constant: -horizontalMargin),

            table.topAnchor.constraint(equalTo: card.topAnchor),
            table.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
        return outer
    }
}

// MARK: - Reusable section views
//
// Each subclass owns its constraints + inner views and exposes an `update`
// method, so the container can mutate an existing instance in place when a
// theme/font swap arrives instead of rebuilding the view hierarchy.

private final class TextSectionView: UIView {
    private let tv = UITextView()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!

    init(attr: NSAttributedString, theme: ReaderTheme, horizontalMargin: CGFloat) {
        super.init(frame: .zero)
        tv.isScrollEnabled = false
        tv.isEditable = false
        tv.isSelectable = true
        tv.dataDetectorTypes = [.link]
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = false
        tv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tv)
        leading = tv.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalMargin)
        trailing = tv.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalMargin)
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: topAnchor),
            tv.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading, trailing
        ])
        update(attr: attr, theme: theme, horizontalMargin: horizontalMargin)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(attr: NSAttributedString, theme: ReaderTheme, horizontalMargin: CGFloat) {
        if tv.attributedText != attr {
            tv.attributedText = attr
        }
        tv.tintColor = theme.uiForeground
        if leading.constant != horizontalMargin { leading.constant = horizontalMargin }
        if trailing.constant != -horizontalMargin { trailing.constant = -horizontalMargin }
    }
}

private final class CodeSectionView: UIView {
    private let card = UIView()
    private let scroll = UIScrollView()
    private let label = UILabel()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    private var currentLanguage: String?
    private var currentRaw: String = ""
    private var currentTheme: ReaderTheme = .light
    private var currentFontSize: CGFloat = 0

    init(language: String?, raw: String, settings: ReaderSettings, theme: ReaderTheme, horizontalMargin: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        card.layer.cornerRadius = 8
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceHorizontal = true
        scroll.showsHorizontalScrollIndicator = true
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        card.addSubview(scroll)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byClipping
        label.adjustsFontForContentSizeCategory = false
        scroll.addSubview(label)

        leading = card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalMargin)
        trailing = card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalMargin)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading, trailing,

            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            label.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),

            scroll.heightAnchor.constraint(equalTo: label.heightAnchor)
        ])

        update(language: language, raw: raw, settings: settings, theme: theme, horizontalMargin: horizontalMargin)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(language: String?, raw: String, settings: ReaderSettings, theme: ReaderTheme, horizontalMargin: CGFloat) {
        card.backgroundColor = theme.codeBackground
        let codeFontSize = max(8, CGFloat(settings.fontSize) - 6)
        let codeFont = UIFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
        label.font = codeFont
        // Only re-highlight when content, language, theme or size actually changed —
        // a margin-only update keeps the cached attributed string.
        if currentRaw != raw || currentLanguage != language || currentTheme != theme || abs(currentFontSize - codeFontSize) > 0.1 {
            label.attributedText = SyntaxHighlighter.highlight(
                code: raw,
                language: language,
                theme: theme,
                font: codeFont
            )
            currentRaw = raw
            currentLanguage = language
            currentTheme = theme
            currentFontSize = codeFontSize
        }
        if leading.constant != horizontalMargin { leading.constant = horizontalMargin }
        if trailing.constant != -horizontalMargin { trailing.constant = -horizontalMargin }
    }
}

private final class QuoteSectionView: UIView {
    private let card = UIView()
    private let bar = UIView()
    private let glyph = UILabel()
    private let tv = UITextView()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!

    init(attr: NSAttributedString, theme: ReaderTheme, horizontalMargin: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        card.layer.cornerRadius = 8
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        bar.layer.cornerRadius = 2
        bar.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(bar)

        glyph.text = "\u{201C}"
        glyph.font = .systemFont(ofSize: 28, weight: .bold)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(glyph)

        tv.isScrollEnabled = false
        tv.isEditable = false
        tv.isSelectable = true
        tv.dataDetectorTypes = [.link]
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = false
        tv.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(tv)

        leading = card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalMargin)
        trailing = card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalMargin)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading, trailing,

            bar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            bar.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            bar.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            bar.widthAnchor.constraint(equalToConstant: 3),

            glyph.topAnchor.constraint(equalTo: card.topAnchor, constant: 0),
            glyph.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),

            tv.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            tv.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            tv.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 14),
            tv.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])

        update(attr: attr, theme: theme, horizontalMargin: horizontalMargin)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(attr: NSAttributedString, theme: ReaderTheme, horizontalMargin: CGFloat) {
        card.backgroundColor = theme.codeBackground
        bar.backgroundColor = theme.uiForeground.withAlphaComponent(0.35)
        glyph.textColor = theme.uiForeground.withAlphaComponent(0.18)
        if tv.attributedText != attr {
            tv.attributedText = attr
        }
        tv.tintColor = theme.uiForeground
        if leading.constant != horizontalMargin { leading.constant = horizontalMargin }
        if trailing.constant != -horizontalMargin { trailing.constant = -horizontalMargin }
    }
}

// MARK: - Wrapping table

/// Renders a markdown table that wraps cell text to fit the available width.
/// Horizontal scroll is only enabled when even the narrowest unbreakable
/// content can't fit — wrapping is preferred over scrolling.
final class WrappingTableView: UIView {
    private let rows: [[String]]
    private let alignments: [MarkdownSection.ColumnAlignment]
    private let headerFont: UIFont
    private let bodyFont: UIFont
    private let theme: ReaderTheme

    private let scrollView = UIScrollView()
    private var cellLabels: [[UILabel]] = []
    private var verticalSeparators: [UIView] = []
    private var horizontalRules: [(rowAfter: Int, view: UIView, height: CGFloat)] = []
    private var rowBackgrounds: [(rowIndex: Int, view: UIView)] = []

    private let cellHPadding: CGFloat = 14
    private let cellVPadding: CGFloat = 8
    private let separatorWidth: CGFloat = 0.5
    private let minColumnWidth: CGFloat = 60

    private var columnMinWidths: [CGFloat] = []
    private var columnMaxWidths: [CGFloat] = []

    private var lastLayoutWidth: CGFloat = -1
    private var computedHeight: CGFloat = 0

    init(rows: [[String]],
         alignments: [MarkdownSection.ColumnAlignment],
         headerFont: UIFont,
         bodyFont: UIFont,
         theme: ReaderTheme) {
        self.rows = rows
        self.alignments = alignments
        self.headerFont = headerFont
        self.bodyFont = bodyFont
        self.theme = theme
        super.init(frame: .zero)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        buildSubviews()
        measureColumnExtremes()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: computedHeight > 0 ? computedHeight : 44)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let available = bounds.width
        guard available > 0 else { return }
        let widthChanged = abs(available - lastLayoutWidth) > 0.5
        let oldHeight = computedHeight
        layoutTable(availableWidth: available)
        if widthChanged || abs(oldHeight - computedHeight) > 0.5 {
            lastLayoutWidth = available
            invalidateIntrinsicContentSize()
        }
    }

    // MARK: - Build

    private func buildSubviews() {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return }

        for (rowIndex, row) in rows.enumerated() {
            let isHeader = rowIndex == 0
            let isAlternate = !isHeader && rowIndex % 2 == 0

            if isHeader {
                let bg = UIView()
                bg.backgroundColor = theme.codeBackground
                scrollView.addSubview(bg)
                rowBackgrounds.append((rowIndex, bg))
            } else if isAlternate {
                let bg = UIView()
                bg.backgroundColor = theme.uiForeground.withAlphaComponent(0.04)
                scrollView.addSubview(bg)
                rowBackgrounds.append((rowIndex, bg))
            }

            var labelsInRow: [UILabel] = []
            for col in 0..<columnCount {
                let raw = col < row.count ? row[col] : ""
                let alignment = col < alignments.count ? alignments[col] : .left

                let label = UILabel()
                label.numberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.text = raw
                label.font = isHeader ? headerFont : bodyFont
                label.textColor = theme.uiForeground
                label.textAlignment = {
                    switch alignment {
                    case .left:   return .left
                    case .center: return .center
                    case .right:  return .right
                    }
                }()
                scrollView.addSubview(label)
                labelsInRow.append(label)

                if col < columnCount - 1 {
                    let sep = UIView()
                    sep.backgroundColor = theme.tableBorderColor
                    scrollView.addSubview(sep)
                    verticalSeparators.append(sep)
                }
            }
            cellLabels.append(labelsInRow)

            if isHeader {
                let underline = UIView()
                underline.backgroundColor = theme.tableBorderColor
                scrollView.addSubview(underline)
                horizontalRules.append((rowIndex, underline, separatorWidth))
            } else if rowIndex < rows.count - 1 {
                let rule = UIView()
                rule.backgroundColor = theme.tableBorderColor.withAlphaComponent(0.4)
                scrollView.addSubview(rule)
                horizontalRules.append((rowIndex, rule, separatorWidth))
            }
        }
    }

    private func measureColumnExtremes() {
        let columnCount = rows.map(\.count).max() ?? 0
        columnMinWidths = Array(repeating: 0, count: columnCount)
        columnMaxWidths = Array(repeating: 0, count: columnCount)

        for (rowIndex, row) in rows.enumerated() {
            let font = rowIndex == 0 ? headerFont : bodyFont
            for (col, raw) in row.enumerated() where col < columnCount {
                // Min: widest unbreakable token (split by whitespace).
                var maxTokenWidth: CGFloat = 0
                for token in raw.split(whereSeparator: { $0.isWhitespace }) {
                    let w = (String(token) as NSString)
                        .size(withAttributes: [.font: font])
                        .width
                    if w > maxTokenWidth { maxTokenWidth = w }
                }
                columnMinWidths[col] = max(columnMinWidths[col], ceil(maxTokenWidth))

                // Max: full single-line text width.
                let fullWidth = (raw as NSString)
                    .size(withAttributes: [.font: font])
                    .width
                columnMaxWidths[col] = max(columnMaxWidths[col], ceil(fullWidth))
            }
        }

        for i in 0..<columnCount {
            columnMinWidths[i] = max(minColumnWidth, columnMinWidths[i] + cellHPadding * 2)
            columnMaxWidths[i] = max(columnMinWidths[i], columnMaxWidths[i] + cellHPadding * 2)
        }
    }

    // MARK: - Layout

    private func columnWidths(forAvailableWidth available: CGFloat) -> [CGFloat] {
        let columnCount = columnMinWidths.count
        guard columnCount > 0 else { return [] }
        let minSum = columnMinWidths.reduce(0, +)
        let maxSum = columnMaxWidths.reduce(0, +)

        if maxSum <= available {
            // Fits fully without wrapping; keep table compact (no stretch).
            return columnMaxWidths
        }
        if minSum <= available {
            // Wrap mode: start from min widths and distribute the slack
            // proportionally to each column's max-min spread.
            var widths = columnMinWidths
            let extra = available - minSum
            let flex = zip(columnMaxWidths, columnMinWidths).map { $0 - $1 }
            let flexSum = flex.reduce(0, +)
            if flexSum > 0 {
                for i in 0..<columnCount {
                    widths[i] += extra * (flex[i] / flexSum)
                }
            } else {
                let per = extra / CGFloat(columnCount)
                for i in 0..<columnCount { widths[i] += per }
            }
            return widths
        }
        // Cannot fit even at minimums — horizontal scroll will take over.
        return columnMinWidths
    }

    private func layoutTable(availableWidth: CGFloat) {
        let columnCount = columnMinWidths.count
        guard columnCount > 0 else {
            scrollView.contentSize = .zero
            computedHeight = 0
            return
        }

        let widths = columnWidths(forAvailableWidth: availableWidth)
        let contentWidth = widths.reduce(0, +)
        let rowWidth = max(contentWidth, availableWidth)
        let needsHorizontalScroll = contentWidth > availableWidth + 0.5

        var y: CGFloat = 0
        var sepIndex = 0
        var ruleIndex = 0
        var bgIndex = 0

        for (rowIndex, labels) in cellLabels.enumerated() {
            var rowHeight: CGFloat = 0
            for (col, label) in labels.enumerated() where col < columnCount {
                let textWidth = max(0, widths[col] - cellHPadding * 2)
                let size = label.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
                let h = ceil(size.height) + cellVPadding * 2
                if h > rowHeight { rowHeight = h }
            }

            // Row background spans the full row width so colour stays solid
            // when the user scrolls horizontally.
            if bgIndex < rowBackgrounds.count, rowBackgrounds[bgIndex].rowIndex == rowIndex {
                rowBackgrounds[bgIndex].view.frame = CGRect(x: 0, y: y, width: rowWidth, height: rowHeight)
                bgIndex += 1
            }

            var x: CGFloat = 0
            for (col, label) in labels.enumerated() where col < columnCount {
                let cellW = widths[col]
                label.frame = CGRect(
                    x: x + cellHPadding,
                    y: y + cellVPadding,
                    width: max(0, cellW - cellHPadding * 2),
                    height: max(0, rowHeight - cellVPadding * 2)
                )
                if col < columnCount - 1, sepIndex < verticalSeparators.count {
                    let sep = verticalSeparators[sepIndex]
                    sep.frame = CGRect(
                        x: x + cellW - separatorWidth,
                        y: y,
                        width: separatorWidth,
                        height: rowHeight
                    )
                    sepIndex += 1
                }
                x += cellW
            }

            y += rowHeight

            if ruleIndex < horizontalRules.count, horizontalRules[ruleIndex].rowAfter == rowIndex {
                let entry = horizontalRules[ruleIndex]
                entry.view.frame = CGRect(x: 0, y: y, width: rowWidth, height: entry.height)
                y += entry.height
                ruleIndex += 1
            }
        }

        scrollView.contentSize = CGSize(width: rowWidth, height: y)
        scrollView.alwaysBounceHorizontal = needsHorizontalScroll
        scrollView.showsHorizontalScrollIndicator = needsHorizontalScroll
        if !needsHorizontalScroll {
            // When the table fits, snap any prior horizontal offset back to zero.
            if scrollView.contentOffset.x != 0 {
                scrollView.contentOffset.x = 0
            }
        }
        computedHeight = y
    }
}

struct PlainTextEditorView: UIViewRepresentable {
    @Binding var text: String
    @Binding var jumpToLine: Int?
    let theme: ReaderTheme
    let fontSize: Double
    let horizontalMargin: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.alwaysBounceVertical = true
        tv.autocapitalizationType = .none
        tv.autocorrectionType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.spellCheckingType = .no
        tv.textContainerInset = UIEdgeInsets(top: 16, left: CGFloat(horizontalMargin), bottom: 80, right: CGFloat(horizontalMargin))
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.backgroundColor = theme.uiBackground
        tv.tintColor = theme.uiForeground

        context.coordinator.bind(textView: tv, theme: theme, fontSize: CGFloat(fontSize))
        tv.text = text
        context.coordinator.applyHighlightNow()
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        tv.backgroundColor = theme.uiBackground

        let inset = UIEdgeInsets(top: 16, left: CGFloat(horizontalMargin), bottom: 80, right: CGFloat(horizontalMargin))
        if tv.textContainerInset != inset {
            tv.textContainerInset = inset
        }

        let themeChanged = context.coordinator.theme != theme
        let fontChanged = abs(context.coordinator.fontSize - CGFloat(fontSize)) > 0.1
        if themeChanged || fontChanged {
            context.coordinator.theme = theme
            context.coordinator.fontSize = CGFloat(fontSize)
            tv.tintColor = theme.uiForeground
            context.coordinator.scheduleHighlight(immediately: true)
        }

        if tv.text != text {
            let selected = tv.selectedRange
            tv.text = text
            tv.selectedRange = selected
            context.coordinator.scheduleHighlight(immediately: true)
        }

        if let line = jumpToLine {
            DispatchQueue.main.async {
                jumpToLine = nil
            }
            scrollToLine(line, in: tv)
        }
    }

    private func scrollToLine(_ line: Int, in tv: UITextView) {
        guard line > 0, let text = tv.text else { return }
        let nsText = text as NSString
        var currentLine = 1
        var offset = 0
        let length = nsText.length
        while currentLine < line, offset < length {
            let r = nsText.range(of: "\n", options: [], range: NSRange(location: offset, length: length - offset))
            if r.location == NSNotFound { return }
            offset = r.location + 1
            currentLine += 1
        }
        let target = NSRange(location: offset, length: 0)
        tv.scrollRangeToVisible(target)
        tv.selectedRange = target
        tv.becomeFirstResponder()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        weak var textView: UITextView?
        var theme: ReaderTheme = .light
        var fontSize: CGFloat = 15
        private var highlightVersion: Int = 0
        /// Raised debounce so fast typing doesn't trigger a highlight pass on
        /// every keystroke — only after the user pauses.
        private let debounceDelay: TimeInterval = 0.25
        /// Fingerprint of the most recent text we fully highlighted. Lets us
        /// short-circuit when nothing actually changed (e.g. selection only).
        private var lastHighlightFingerprint: HighlightFingerprint?

        private struct HighlightFingerprint: Equatable {
            let length: Int
            let hash: Int
            let theme: ReaderTheme
            let fontSize: CGFloat
        }

        init(text: Binding<String>) {
            _text = text
            super.init()
        }

        func bind(textView: UITextView, theme: ReaderTheme, fontSize: CGFloat) {
            self.textView = textView
            self.theme = theme
            self.fontSize = fontSize
        }

        var monoFont: UIFont {
            UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        func textViewDidChange(_ tv: UITextView) {
            text = tv.text
            scheduleHighlight(immediately: false)
        }

        func scheduleHighlight(immediately: Bool) {
            highlightVersion &+= 1
            let v = highlightVersion
            let delay = immediately ? 0 : debounceDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, v == self.highlightVersion else { return }
                self.applyHighlightNow()
            }
        }

        func applyHighlightNow() {
            guard let tv = textView else { return }
            // Skip mid-composition (IME): re-highlighting would disrupt the
            // marked-text range and feel laggy on languages with composition.
            if tv.markedTextRange != nil { return }

            let textNow = tv.text ?? ""
            let fingerprint = HighlightFingerprint(
                length: textNow.utf16.count,
                hash: textNow.hashValue,
                theme: theme,
                fontSize: fontSize
            )
            if fingerprint == lastHighlightFingerprint {
                return
            }

            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: monoFont,
                .foregroundColor: theme.uiForeground
            ]
            tv.typingAttributes = baseAttrs

            let fullRange = NSRange(location: 0, length: tv.textStorage.length)
            guard !textNow.isEmpty else {
                lastHighlightFingerprint = fingerprint
                return
            }

            // Highlighter.highlight needs to round-trip the exact same string;
            // if it doesn't (rare), fall back to base attributes only.
            let highlighted = SyntaxHighlighter.highlightForEditor(
                code: textNow,
                theme: theme,
                font: monoFont
            )

            let selected = tv.selectedRange
            tv.textStorage.beginEditing()
            tv.textStorage.setAttributes(baseAttrs, range: fullRange)
            if let highlighted, highlighted.string == textNow {
                highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length), options: []) { attrs, range, _ in
                    var clean = attrs
                    clean.removeValue(forKey: .backgroundColor)
                    clean[.font] = monoFont
                    if clean[.foregroundColor] == nil {
                        clean[.foregroundColor] = theme.uiForeground
                    }
                    tv.textStorage.setAttributes(clean, range: range)
                }
            }
            overlayFencedCodeHighlights(in: tv.textStorage, source: textNow, font: monoFont)
            tv.textStorage.endEditing()
            tv.selectedRange = selected
            lastHighlightFingerprint = fingerprint
        }

        /// Re-highlight the contents of each fenced ``` block with its own
        /// language so code inside the editor gets proper syntax colours on
        /// top of the markdown pass.
        private func overlayFencedCodeHighlights(in storage: NSTextStorage, source: String, font: UIFont) {
            let nsText = source as NSString
            let matches = Self.fencedCodeRegex.matches(
                in: source,
                options: [],
                range: NSRange(location: 0, length: nsText.length)
            )
            guard !matches.isEmpty else { return }

            for match in matches {
                let langRange = match.range(at: 1)
                let codeRange = match.range(at: 2)
                guard codeRange.location != NSNotFound, codeRange.length > 0 else { continue }
                let language: String? = (langRange.location != NSNotFound && langRange.length > 0)
                    ? nsText.substring(with: langRange).lowercased()
                    : nil
                let codeStr = nsText.substring(with: codeRange)
                let attr = SyntaxHighlighter.highlight(
                    code: codeStr,
                    language: language,
                    theme: theme,
                    font: font
                )
                guard attr.length == codeRange.length else { continue }
                attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length),
                                        options: []) { attrs, localRange, _ in
                    let dst = NSRange(location: codeRange.location + localRange.location,
                                      length: localRange.length)
                    if let color = attrs[.foregroundColor] {
                        storage.addAttribute(.foregroundColor, value: color, range: dst)
                    }
                    if let f = attrs[.font] as? UIFont {
                        storage.addAttribute(.font, value: f, range: dst)
                    }
                }
            }
        }

        private static let fencedCodeRegex: NSRegularExpression = {
            // ^[indent]```lang\n<code>\n[indent]```
            let pattern = #"(?m)^[ \t]{0,3}```([\w-]*)[^\n]*\n([\s\S]*?)\n[ \t]{0,3}```[ \t]*$"#
            return try! NSRegularExpression(pattern: pattern, options: [])
        }()
    }
}

// MARK: - Highlighter helpers

enum SyntaxHighlighter {
    private static let editorHighlighter: Highlighter? = Highlighter()
    private static let readerHighlighter: Highlighter? = Highlighter()
    /// Tracks the most recently applied theme name per highlighter so we can
    /// skip the (non-trivial) `setTheme` call when nothing changed.
    private static var lastEditorTheme: String?
    private static var lastReaderTheme: String?

    static func highlightForEditor(code: String, theme: ReaderTheme, font: UIFont) -> NSAttributedString? {
        guard let h = editorHighlighter else { return nil }
        let name = themeName(for: theme)
        if lastEditorTheme != name {
            h.setTheme(name)
            lastEditorTheme = name
        }
        return h.highlight(code, as: "markdown")
    }

    static func highlight(code: String, language: String?, theme: ReaderTheme, font: UIFont) -> NSAttributedString {
        let fallback = NSAttributedString(
            string: code,
            attributes: [.font: font, .foregroundColor: theme.codeForeground]
        )
        guard let h = readerHighlighter else { return fallback }
        let name = themeName(for: theme)
        if lastReaderTheme != name {
            h.setTheme(name)
            lastReaderTheme = name
        }
        guard let source = h.highlight(code, as: language) else { return fallback }

        let fullRange = NSRange(location: 0, length: source.length)

        // Rebuild from scratch with our font as the single source of truth for size.
        // Highlighter bakes its own theme codeFont (default 14pt) and paragraph style;
        // we keep only the foreground colours.
        let result = NSMutableAttributedString(string: source.string,
                                               attributes: [.font: font,
                                                            .foregroundColor: theme.codeForeground])

        source.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let traits = (value as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            guard !traits.isEmpty,
                  let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return }
            result.addAttribute(.font,
                                value: UIFont(descriptor: descriptor, size: font.pointSize),
                                range: range)
        }

        source.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if let color = value {
                result.addAttribute(.foregroundColor, value: color, range: range)
            }
        }

        return result
    }

    private static func themeName(for theme: ReaderTheme) -> String {
        switch theme {
        case .light, .sepia: return "xcode"
        case .dark:          return "stackoverflow-dark"
        }
    }
}
