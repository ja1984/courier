import Foundation

/// Re-indents XML/HTML by changing only the whitespace between tags.
/// Tag text, attributes, entities and the contents of script/style/pre/textarea are kept verbatim.
public enum MarkupFormatter {
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr",
    ]
    private static let rawTextElements: Set<String> = ["script", "style", "pre", "textarea"]

    private enum Token {
        case open(text: String, name: String, selfClosing: Bool)
        case close(text: String, name: String)
        case other(String)  // comment, CDATA, doctype, processing instruction
        case text(String)
        case raw(String)    // a whole raw-text element, kept as-is
    }

    public static func prettyPrinted(_ markup: String, isHTML: Bool, indent: String = "  ") -> String {
        let tokens = tokenize(Array(markup.utf16), isHTML: isHTML)
        var lines: [String] = []
        var level = 0
        var index = 0

        func emit(_ text: String) {
            lines.append(String(repeating: indent, count: max(level, 0)) + text)
        }

        while index < tokens.count {
            switch tokens[index] {
            case let .open(text, name, selfClosing):
                let isVoid = isHTML && voidElements.contains(name.lowercased())
                if selfClosing || isVoid {
                    emit(text)
                } else if index + 2 < tokens.count,
                          case let .text(inner) = tokens[index + 1],
                          case let .close(closeText, closeName) = tokens[index + 2],
                          closeName.caseInsensitiveCompare(name) == .orderedSame,
                          !inner.contains("\n"), inner.count <= 100 {
                    // Short text-only element stays on one line: <p>Hello</p>
                    emit(text + inner + closeText)
                    index += 2
                } else {
                    emit(text)
                    level += 1
                }
            case let .close(text, _):
                level -= 1
                emit(text)
            case let .other(text), let .raw(text):
                emit(text)
            case let .text(text):
                for line in text.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { emit(trimmed) }
                }
            }
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    private static func tokenize(_ u: [UInt16], isHTML: Bool) -> [Token] {
        var tokens: [Token] = []
        var i = 0

        func string(_ range: Range<Int>) -> String { String(decoding: u[range], as: UTF16.self) }
        func hasPrefix(_ prefix: String, at index: Int, caseInsensitive: Bool = false) -> Bool {
            let p = Array(prefix.utf16)
            guard index + p.count <= u.count else { return false }
            for k in 0..<p.count {
                var a = u[index + k]
                if caseInsensitive, a >= 0x41, a <= 0x5A { a += 0x20 }
                if a != p[k] { return false }
            }
            return true
        }
        func find(_ terminator: String, from index: Int, caseInsensitive: Bool = false) -> Int? {
            var j = index
            while j < u.count {
                if hasPrefix(terminator, at: j, caseInsensitive: caseInsensitive) { return j }
                j += 1
            }
            return nil
        }
        func isTagStart(_ index: Int) -> Bool {
            guard index + 1 < u.count, u[index] == 0x3C else { return false }
            let c = u[index + 1]
            return (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x2F || c == 0x21 || c == 0x3F
        }
        /// End of a tag (index after `>`), skipping `>` inside quoted attribute values.
        func tagEnd(from index: Int) -> Int {
            var j = index
            var quote: UInt16?
            while j < u.count {
                let c = u[j]
                if let q = quote {
                    if c == q { quote = nil }
                } else if c == 0x22 || c == 0x27 {
                    quote = c
                } else if c == 0x3E {
                    return j + 1
                }
                j += 1
            }
            return u.count
        }
        func tagName(in range: Range<Int>) -> String {
            var j = range.lowerBound + 1
            if j < range.upperBound, u[j] == 0x2F { j += 1 }
            let start = j
            while j < range.upperBound {
                let c = u[j]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2F || c == 0x3E { break }
                j += 1
            }
            return string(start..<j)
        }

        while i < u.count {
            if hasPrefix("<!--", at: i) {
                let end = find("-->", from: i + 4).map { $0 + 3 } ?? u.count
                tokens.append(.other(string(i..<end)))
                i = end
            } else if hasPrefix("<![CDATA[", at: i) {
                let end = find("]]>", from: i + 9).map { $0 + 3 } ?? u.count
                tokens.append(.other(string(i..<end)))
                i = end
            } else if isTagStart(i) {
                let end = tagEnd(from: i)
                let text = string(i..<end)
                let second = u[i + 1]
                if second == 0x21 || second == 0x3F {
                    tokens.append(.other(text))
                } else if second == 0x2F {
                    tokens.append(.close(text: text, name: tagName(in: i..<end)))
                } else {
                    let name = tagName(in: i..<end)
                    let selfClosing = text.hasSuffix("/>")
                    if isHTML, !selfClosing, rawTextElements.contains(name.lowercased()),
                       let closeStart = find("</" + name.lowercased(), from: end, caseInsensitive: true) {
                        let closeEnd = tagEnd(from: closeStart)
                        tokens.append(.raw(string(i..<closeEnd)))
                        i = closeEnd
                        continue
                    }
                    tokens.append(.open(text: text, name: name, selfClosing: selfClosing))
                }
                i = end
            } else {
                var j = i + 1
                while j < u.count, !isTagStart(j), !hasPrefix("<!--", at: j) { j += 1 }
                let text = string(i..<j).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { tokens.append(.text(text)) }
                i = j
            }
        }
        return tokens
    }
}
