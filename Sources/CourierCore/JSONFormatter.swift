import Foundation

public enum JSONFormatter {
    public static func isValid(_ text: String) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) != nil
    }

    /// Re-indents valid JSON without reordering keys or touching values. Returns nil for invalid JSON.
    public static func prettyPrinted(_ text: String, indent: String = "  ") -> String? {
        guard isValid(text) else { return nil }
        return reformat(Array(text.utf8), indent: Array(indent.utf8))
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func reformat(_ bytes: [UInt8], indent: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count * 2)
        var level = 0
        var inString = false
        var escaped = false

        func newline() {
            out.append(0x0A)
            for _ in 0..<max(level, 0) { out.append(contentsOf: indent) }
        }

        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if inString {
                out.append(b)
                if escaped {
                    escaped = false
                } else if b == 0x5C {
                    escaped = true
                } else if b == 0x22 {
                    inString = false
                }
                i += 1
                continue
            }
            switch b {
            case 0x22:
                inString = true
                out.append(b)
            case 0x7B, 0x5B: // { [
                out.append(b)
                var j = i + 1
                while j < bytes.count, isWhitespace(bytes[j]) { j += 1 }
                let closer: UInt8 = b == 0x7B ? 0x7D : 0x5D
                if j < bytes.count, bytes[j] == closer {
                    out.append(closer)
                    i = j
                } else {
                    level += 1
                    newline()
                }
            case 0x7D, 0x5D: // } ]
                level -= 1
                newline()
                out.append(b)
            case 0x2C: // ,
                out.append(b)
                newline()
            case 0x3A: // :
                out.append(b)
                out.append(0x20)
            case _ where isWhitespace(b):
                break
            default:
                out.append(b)
            }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }
}

public enum SyntaxKind: Sendable {
    case key, string, number, literal, punctuation, tag, attribute, comment
}

public struct SyntaxToken: Equatable, Sendable {
    public let kind: SyntaxKind
    public let range: NSRange
}

/// A forgiving tokenizer for syntax highlighting; works on partially-typed JSON too.
public enum JSONHighlighter {
    public static func tokens(in text: String) -> [SyntaxToken] {
        let units = Array(text.utf16)
        var tokens: [SyntaxToken] = []
        var i = 0

        func isSpace(_ u: UInt16) -> Bool { u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D }
        func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }
        func isLetter(_ u: UInt16) -> Bool { (u >= 0x61 && u <= 0x7A) || (u >= 0x41 && u <= 0x5A) }

        while i < units.count {
            let c = units[i]
            let start = i
            if c == 0x22 {
                i += 1
                while i < units.count {
                    if units[i] == 0x5C { i += 2; continue }
                    if units[i] == 0x22 { i += 1; break }
                    i += 1
                }
                let end = min(i, units.count)
                var j = end
                while j < units.count, isSpace(units[j]) { j += 1 }
                let kind: SyntaxKind = j < units.count && units[j] == 0x3A ? .key : .string
                tokens.append(SyntaxToken(kind: kind, range: NSRange(location: start, length: end - start)))
            } else if c == 0x2D || isDigit(c) {
                i += 1
                while i < units.count, isDigit(units[i]) || [0x2E, 0x65, 0x45, 0x2B, 0x2D].contains(units[i]) { i += 1 }
                tokens.append(SyntaxToken(kind: .number, range: NSRange(location: start, length: i - start)))
            } else if isLetter(c) {
                while i < units.count, isLetter(units[i]) { i += 1 }
                let word = String(decoding: units[start..<i], as: UTF16.self)
                if word == "true" || word == "false" || word == "null" {
                    tokens.append(SyntaxToken(kind: .literal, range: NSRange(location: start, length: i - start)))
                }
            } else if [0x7B, 0x7D, 0x5B, 0x5D, 0x2C, 0x3A].contains(c) {
                i += 1
                tokens.append(SyntaxToken(kind: .punctuation, range: NSRange(location: start, length: 1)))
            } else {
                i += 1
            }
        }
        return tokens
    }
}
