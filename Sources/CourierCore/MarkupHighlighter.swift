import Foundation

/// A forgiving XML/HTML tokenizer for syntax highlighting.
public enum MarkupHighlighter {
    public static func tokens(in text: String) -> [SyntaxToken] {
        let units = Array(text.utf16)
        var tokens: [SyntaxToken] = []
        var i = 0

        let lt: UInt16 = 0x3C, gt: UInt16 = 0x3E, slash: UInt16 = 0x2F, eq: UInt16 = 0x3D
        func isSpace(_ u: UInt16) -> Bool { u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D }
        func isNameChar(_ u: UInt16) -> Bool {
            (u >= 0x61 && u <= 0x7A) || (u >= 0x41 && u <= 0x5A) || (u >= 0x30 && u <= 0x39)
                || u == 0x2D || u == 0x5F || u == 0x3A || u == 0x2E || u > 0x7F
        }
        func hasPrefix(_ prefix: String, at index: Int) -> Bool {
            let p = Array(prefix.utf16)
            guard index + p.count <= units.count else { return false }
            return Array(units[index..<index + p.count]) == p
        }
        func skip(past terminator: String, from index: Int) -> Int {
            let t = Array(terminator.utf16)
            var j = index
            while j + t.count <= units.count {
                if Array(units[j..<j + t.count]) == t { return j + t.count }
                j += 1
            }
            return units.count
        }
        func add(_ kind: SyntaxKind, _ start: Int, _ end: Int) {
            if end > start { tokens.append(SyntaxToken(kind: kind, range: NSRange(location: start, length: end - start))) }
        }

        while i < units.count {
            guard units[i] == lt else {
                i += 1
                continue
            }
            let start = i
            if hasPrefix("<!--", at: i) {
                i = skip(past: "-->", from: i + 4)
                add(.comment, start, i)
                continue
            }
            if hasPrefix("<![CDATA[", at: i) {
                i = skip(past: "]]>", from: i + 9)
                add(.string, start, i)
                continue
            }

            // Opening "<", "</", "<?" or "<!" plus the tag name.
            i += 1
            if i < units.count, units[i] == slash || units[i] == 0x3F || units[i] == 0x21 { i += 1 }
            while i < units.count, isNameChar(units[i]) { i += 1 }
            add(.tag, start, i)

            // Attributes until the closing ">".
            while i < units.count, units[i] != gt {
                let u = units[i]
                if isSpace(u) || u == eq {
                    i += 1
                } else if u == 0x22 || u == 0x27 {
                    let valueStart = i
                    i += 1
                    while i < units.count, units[i] != u { i += 1 }
                    i = min(i + 1, units.count)
                    add(.string, valueStart, i)
                } else if isNameChar(u) {
                    let nameStart = i
                    while i < units.count, isNameChar(units[i]) { i += 1 }
                    add(.attribute, nameStart, i)
                } else if (u == slash || u == 0x3F), i + 1 < units.count, units[i + 1] == gt {
                    break
                } else if u == lt {
                    break // Malformed: a new tag started before this one closed.
                } else {
                    i += 1
                }
            }
            if i < units.count, units[i] != lt {
                let closeStart = i
                if units[i] != gt { i += 1 } // "/" or "?"
                i = min(i + 1, units.count)
                add(.tag, closeStart, i)
            }
        }
        return tokens
    }
}
