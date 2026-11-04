import Foundation

/// An order-preserving JSON tree that keeps each value's original source text,
/// used for the collapsible response viewer.
public struct JSONNode: Identifiable, Sendable {
    public enum Kind: Sendable {
        case object, array, string, number, bool, null
    }

    /// Pre-order index, unique within the tree.
    public let id: Int
    public let kind: Kind
    public let depth: Int
    /// The object key exactly as written in the source, quotes included. Nil for array items and the root.
    public let rawKey: String?
    /// Source text for scalars. Empty for containers.
    public let raw: String
    public let children: [JSONNode]
    let sourceRange: Range<Int>

    public var isContainer: Bool { kind == .object || kind == .array }
}

public struct JSONTree: Sendable {
    public let root: JSONNode
    public let nodeCount: Int
    /// Ids of every object/array that has children.
    public let collapsibleIDs: Set<Int>
    private let source: [UInt8]
    /// Parent id for each node id (-1 for the root).
    private let parents: [Int]

    public init?(_ text: String, maxDepth: Int = 128) {
        var parser = Parser(bytes: Array(text.utf8), maxDepth: maxDepth)
        guard let root = try? parser.parseDocument() else { return nil }
        self.root = root
        self.source = parser.bytes
        self.nodeCount = parser.nextID
        var ids = Set<Int>()
        var parents = [Int](repeating: -1, count: parser.nextID)
        func collect(_ node: JSONNode) {
            if node.isContainer, !node.children.isEmpty { ids.insert(node.id) }
            for child in node.children {
                parents[child.id] = node.id
                collect(child)
            }
        }
        collect(root)
        self.collapsibleIDs = ids
        self.parents = parents
    }

    /// Ids of nodes whose key or scalar value contains `query` (case-insensitive), in document order.
    public func matches(for query: String, limit: Int = 10_000) -> [Int] {
        guard !query.isEmpty else { return [] }
        var result: [Int] = []
        func visit(_ node: JSONNode) {
            guard result.count < limit else { return }
            let keyMatches = node.rawKey?.range(of: query, options: .caseInsensitive) != nil
            let valueMatches = !node.isContainer && node.raw.range(of: query, options: .caseInsensitive) != nil
            if keyMatches || valueMatches { result.append(node.id) }
            node.children.forEach(visit)
        }
        visit(root)
        return result
    }

    /// Container ids that must be expanded for `id` to be visible, outermost first.
    public func ancestors(of id: Int) -> [Int] {
        var chain: [Int] = []
        var current = id < parents.count ? parents[id] : -1
        while current >= 0 {
            chain.append(current)
            current = parents[current]
        }
        return chain.reversed()
    }

    /// The node's JSON, pretty-printed when it's a container.
    public func text(of node: JSONNode) -> String {
        let slice = String(decoding: source[node.sourceRange], as: UTF8.self)
        return node.isContainer ? (JSONFormatter.prettyPrinted(slice) ?? slice) : slice
    }

    /// Ids to collapse so that only `depth` levels are open.
    public func collapsibleIDs(atOrBelowDepth depth: Int) -> Set<Int> {
        var ids = Set<Int>()
        func walk(_ node: JSONNode) {
            if node.isContainer, !node.children.isEmpty, node.depth >= depth { ids.insert(node.id) }
            node.children.forEach(walk)
        }
        walk(root)
        return ids
    }

    // MARK: Lines

    public struct Line: Identifiable, Sendable {
        public enum Kind: Sendable {
            /// A scalar or an empty container (`{}` / `[]`).
            case value
            case open
            case collapsed
            case close
        }

        public let id: Int
        public let node: JSONNode
        public let kind: Kind
        public let hasTrailingComma: Bool
    }

    /// The visible lines given a set of collapsed container ids.
    public func lines(collapsed: Set<Int>) -> [Line] {
        var lines: [Line] = []
        lines.reserveCapacity(nodeCount)
        func visit(_ node: JSONNode, comma: Bool) {
            guard node.isContainer, !node.children.isEmpty else {
                lines.append(Line(id: node.id * 2, node: node, kind: .value, hasTrailingComma: comma))
                return
            }
            if collapsed.contains(node.id) {
                lines.append(Line(id: node.id * 2, node: node, kind: .collapsed, hasTrailingComma: comma))
                return
            }
            lines.append(Line(id: node.id * 2, node: node, kind: .open, hasTrailingComma: false))
            for (index, child) in node.children.enumerated() {
                visit(child, comma: index < node.children.count - 1)
            }
            lines.append(Line(id: node.id * 2 + 1, node: node, kind: .close, hasTrailingComma: comma))
        }
        visit(root, comma: false)
        return lines
    }

    // MARK: Parser

    private struct ParseError: Error {}

    private struct Parser {
        let bytes: [UInt8]
        let maxDepth: Int
        var pos = 0
        var nextID = 0

        mutating func parseDocument() throws -> JSONNode {
            let node = try parseValue(depth: 0, rawKey: nil)
            skipWhitespace()
            guard pos == bytes.count else { throw ParseError() }
            return node
        }

        mutating func skipWhitespace() {
            while pos < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[pos]) { pos += 1 }
        }

        mutating func expect(_ byte: UInt8) throws {
            skipWhitespace()
            guard pos < bytes.count, bytes[pos] == byte else { throw ParseError() }
            pos += 1
        }

        func peek() -> UInt8? { pos < bytes.count ? bytes[pos] : nil }

        mutating func parseValue(depth: Int, rawKey: String?) throws -> JSONNode {
            guard depth <= maxDepth else { throw ParseError() }
            skipWhitespace()
            guard let byte = peek() else { throw ParseError() }
            let id = nextID
            nextID += 1
            let start = pos

            switch byte {
            case 0x7B, 0x5B: // { [
                let isObject = byte == 0x7B
                let closer: UInt8 = isObject ? 0x7D : 0x5D
                pos += 1
                var children: [JSONNode] = []
                skipWhitespace()
                if peek() == closer {
                    pos += 1
                } else {
                    while true {
                        var key: String?
                        if isObject {
                            skipWhitespace()
                            key = try parseStringToken()
                            try expect(0x3A)
                        }
                        children.append(try parseValue(depth: depth + 1, rawKey: key))
                        skipWhitespace()
                        if peek() == 0x2C { pos += 1; continue }
                        try expect(closer)
                        break
                    }
                }
                return JSONNode(
                    id: id, kind: isObject ? .object : .array, depth: depth, rawKey: rawKey,
                    raw: "", children: children, sourceRange: start..<pos
                )
            case 0x22:
                let raw = try parseStringToken()
                return JSONNode(id: id, kind: .string, depth: depth, rawKey: rawKey, raw: raw, children: [], sourceRange: start..<pos)
            default:
                while pos < bytes.count, !([0x2C, 0x7D, 0x5D, 0x20, 0x09, 0x0A, 0x0D].contains(bytes[pos])) { pos += 1 }
                let raw = String(decoding: bytes[start..<pos], as: UTF8.self)
                let kind: JSONNode.Kind
                switch raw {
                case "true", "false": kind = .bool
                case "null": kind = .null
                default:
                    guard Double(raw) != nil else { throw ParseError() }
                    kind = .number
                }
                return JSONNode(id: id, kind: kind, depth: depth, rawKey: rawKey, raw: raw, children: [], sourceRange: start..<pos)
            }
        }

        mutating func parseStringToken() throws -> String {
            guard peek() == 0x22 else { throw ParseError() }
            let start = pos
            pos += 1
            while pos < bytes.count, bytes[pos] != 0x22 {
                pos += bytes[pos] == 0x5C ? 2 : 1
            }
            guard pos < bytes.count else { throw ParseError() }
            pos += 1
            return String(decoding: bytes[start..<pos], as: UTF8.self)
        }
    }
}
