import Testing
@testable import CourierCore

@Suite struct JSONTreeTests {
    let json = #"{"name":"Ada","tags":["a","b\"c"],"meta":{"n":-1.5e3,"ok":true,"none":null},"empty":{}}"#

    @Test func preservesOrderAndSourceText() throws {
        let tree = try #require(JSONTree(json))
        #expect(tree.root.kind == .object)
        #expect(tree.root.children.map(\.rawKey) == [#""name""#, #""tags""#, #""meta""#, #""empty""#])
        #expect(tree.root.children[1].children[1].raw == #""b\"c""#)
        #expect(tree.root.children[2].children.map(\.kind) == [.number, .bool, .null])
        #expect(tree.nodeCount == 10)
        #expect(tree.collapsibleIDs.count == 3) // root, tags, meta (empty {} isn't collapsible)
    }

    @Test func linesWhenExpanded() throws {
        let tree = try #require(JSONTree(json))
        let lines = tree.lines(collapsed: [])
        #expect(lines.map(\.kind) == [
            .open, .value, .open, .value, .value, .close, .open, .value, .value, .value, .close, .value, .close,
        ])
        // Commas: last child of each container has none; a closing line gets its container's comma.
        #expect(lines.map(\.hasTrailingComma) == [
            false, true, false, true, false, true, false, true, true, false, true, false, false,
        ])
        #expect(Set(lines.map(\.id)).count == lines.count)
    }

    @Test func collapsingHidesChildren() throws {
        let tree = try #require(JSONTree(json))
        let tags = tree.root.children[1]
        let lines = tree.lines(collapsed: [tags.id])
        #expect(lines[2].kind == .collapsed)
        #expect(lines[2].hasTrailingComma)
        #expect(lines.count == 10)
        #expect(tree.lines(collapsed: [tree.root.id]).count == 1)
    }

    @Test func collapseByDepth() throws {
        let tree = try #require(JSONTree(json))
        #expect(tree.collapsibleIDs(atOrBelowDepth: 1) == [tree.root.children[1].id, tree.root.children[2].id])
    }

    @Test func copyTextOfNode() throws {
        let tree = try #require(JSONTree(json))
        #expect(tree.text(of: tree.root.children[0]) == #""Ada""#)
        #expect(tree.text(of: tree.root.children[1]) == "[\n  \"a\",\n  \"b\\\"c\"\n]")
    }

    @Test func rejectsInvalidJSON() {
        #expect(JSONTree("{\"a\":}") == nil)
        #expect(JSONTree("[1,2") == nil)
        #expect(JSONTree("[1] x") == nil)
        #expect(JSONTree("[nope]") == nil)
        #expect(JSONTree(String(repeating: "[", count: 600) + String(repeating: "]", count: 600)) == nil)
        #expect(JSONTree(String(repeating: "[", count: 100) + String(repeating: "]", count: 100)) != nil)
    }
}
