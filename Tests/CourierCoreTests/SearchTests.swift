import Foundation
import Testing
@testable import CourierCore

@Suite struct SearchTests {
    @Test func textRangesAreCaseInsensitiveAndNonOverlapping() {
        let ranges = TextSearch.ranges(of: "aa", in: "AAAa ba")
        #expect(ranges == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2)])
    }

    @Test func textRangesUseUTF16Offsets() {
        let ranges = TextSearch.ranges(of: "x", in: "🎉x")
        #expect(ranges == [NSRange(location: 2, length: 1)])
    }

    @Test func emptyQueryAndLimit() {
        #expect(TextSearch.ranges(of: "", in: "abc").isEmpty)
        #expect(TextSearch.ranges(of: "a", in: String(repeating: "a", count: 50), limit: 10).count == 10)
    }

    @Test func jsonMatchesKeysAndScalarValues() throws {
        let tree = try #require(JSONTree(#"{"user":{"Name":"Ada","tags":["admin","dev"]},"count":3}"#))
        let ids = tree.matches(for: "ad")
        let nodes = ids.map { id in tree.lines(collapsed: []).first { $0.node.id == id }?.node }
        #expect(nodes.compactMap { $0?.raw } == [#""Ada""#, #""admin""#])
        #expect(tree.matches(for: "name").count == 1) // key match, case-insensitive
        #expect(tree.matches(for: "zzz").isEmpty)
    }

    @Test func ancestorsLeadToTheMatch() throws {
        let tree = try #require(JSONTree(#"{"a":{"b":[1,{"c":"needle"}]}}"#))
        let match = try #require(tree.matches(for: "needle").first)
        let chain = tree.ancestors(of: match)
        #expect(chain.first == tree.root.id)
        #expect(chain.count == 4) // root, a, b, {c}
        #expect(tree.lines(collapsed: Set(tree.collapsibleIDs).subtracting(chain)).contains { $0.node.id == match })
    }
}
