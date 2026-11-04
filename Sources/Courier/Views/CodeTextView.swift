import AppKit
import CourierCore
import SwiftUI

enum CodeLanguage {
    case plain, json, markup

    init(_ format: ResponseFormat) {
        switch format {
        case .json: self = .json
        case .xml, .html: self = .markup
        case .text, .binary: self = .plain
        }
    }
}

/// NSTextView wrapper: handles large bodies, has find (⌘F), and no smart-quote substitution.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var language: CodeLanguage
    /// Matches to highlight, and which one is current (scrolled into view).
    var searchRanges: [NSRange] = []
    var currentSearchIndex: Int?

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    /// Above this size, skip highlighting to keep the UI responsive.
    static let highlightLimit = 1_000_000

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        // Read-only views use the response search bar instead of the system find bar.
        textView.usesFindBar = isEditable
        textView.isIncrementalSearchingEnabled = isEditable
        textView.setAccessibilityLabel(isEditable ? "Request body" : "Response body")

        context.coordinator.apply(text, language: language, to: textView)
        context.coordinator.applySearch(searchRanges, current: currentSearchIndex, to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        if textView.string != text || context.coordinator.language != language {
            context.coordinator.apply(text, language: language, to: textView)
            context.coordinator.applySearch(searchRanges, current: currentSearchIndex, to: textView)
        } else if context.coordinator.searchRanges != searchRanges || context.coordinator.currentSearchIndex != currentSearchIndex {
            context.coordinator.applySearch(searchRanges, current: currentSearchIndex, to: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        private(set) var language: CodeLanguage
        private(set) var searchRanges: [NSRange] = []
        private(set) var currentSearchIndex: Int?

        init(parent: CodeTextView) {
            self.parent = parent
            self.language = parent.language
        }

        func apply(_ text: String, language: CodeLanguage, to textView: NSTextView) {
            self.language = language
            textView.string = text
            highlight(textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlight(textView)
        }

        /// Marks search matches with a background colour and scrolls the current one into view.
        func applySearch(_ ranges: [NSRange], current: Int?, to textView: NSTextView) {
            searchRanges = ranges
            currentSearchIndex = current
            guard let storage = textView.textStorage else { return }
            let length = storage.length
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: length))
            for (index, range) in ranges.enumerated() where NSMaxRange(range) <= length {
                let color = index == current ? Theme.searchCurrent : Theme.searchMatch
                storage.addAttribute(.backgroundColor, value: color, range: range)
            }
            storage.endEditing()
            if let current, ranges.indices.contains(current), NSMaxRange(ranges[current]) <= length {
                textView.scrollRangeToVisible(ranges[current])
                textView.showFindIndicator(for: ranges[current])
            }
        }

        private func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([.font: CodeTextView.font, .foregroundColor: NSColor.textColor], range: full)
            if storage.length <= CodeTextView.highlightLimit {
                let tokens: [SyntaxToken] = switch language {
                case .json: JSONHighlighter.tokens(in: storage.string)
                case .markup: MarkupHighlighter.tokens(in: storage.string)
                case .plain: []
                }
                for token in tokens {
                    storage.addAttribute(.foregroundColor, value: Self.color(for: token.kind), range: token.range)
                }
            }
            storage.endEditing()
            textView.typingAttributes = [.font: CodeTextView.font, .foregroundColor: NSColor.textColor]
        }

        private static func color(for kind: SyntaxKind) -> NSColor {
            switch kind {
            case .key: Theme.codeKey
            case .string: Theme.codeString
            case .number: Theme.codeNumber
            case .literal: Theme.codeLiteral
            case .punctuation: .secondaryLabelColor
            case .tag: Theme.codeTag
            case .attribute: Theme.codeAttribute
            case .comment: Theme.codeComment
            }
        }
    }
}
