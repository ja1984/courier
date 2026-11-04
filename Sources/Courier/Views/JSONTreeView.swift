import AppKit
import CourierCore
import SwiftUI

/// Collapsible JSON viewer. Lines are virtualised, so large bodies stay responsive.
struct JSONTreeView: View {
    /// Expand/collapse-all requested from outside (the response header). A new id runs it once.
    struct Command: Equatable {
        var id = 0
        var expand = true
    }

    let tree: JSONTree
    var command = Command()
    /// Node ids matching the current search, and the one to reveal.
    var searchMatches: [Int] = []
    var currentMatch: Int?
    @State private var collapsed: Set<Int>

    /// Above this many nodes, start with only the top two levels open.
    private static let autoCollapseThreshold = 5_000

    init(tree: JSONTree, command: Command = Command(), searchMatches: [Int] = [], currentMatch: Int? = nil) {
        self.tree = tree
        self.command = command
        self.searchMatches = searchMatches
        self.currentMatch = currentMatch
        _collapsed = State(initialValue: tree.nodeCount > Self.autoCollapseThreshold
            ? tree.collapsibleIDs(atOrBelowDepth: 2)
            : [])
    }

    var body: some View {
        let lines = tree.lines(collapsed: collapsed)
        let matchSet = Set(searchMatches)
        // Vertical only: long values wrap, so there's never a sideways scroll bar.
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        JSONLineRow(
                            line: line,
                            isCollapsed: collapsed.contains(line.node.id),
                            searchState: line.kind == .close ? .none
                                : line.node.id == currentMatch ? .current
                                : matchSet.contains(line.node.id) ? .match : .none,
                            onToggle: { toggle(line.node.id) },
                            copy: { copy(tree.text(of: line.node)) },
                            setDescendants: { expanded in setDescendants(of: line.node, expanded: expanded) }
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.trailing, 16)
            }
            .onAppear { reveal(currentMatch, using: proxy) }
            .onChange(of: currentMatch) { _, id in reveal(id, using: proxy) }
        }
        .onChange(of: command) { _, command in
            collapsed = command.expand ? [] : tree.collapsibleIDs.subtracting([tree.root.id])
        }
    }

    /// Expands the match's parents, then scrolls its line into view.
    private func reveal(_ id: Int?, using proxy: ScrollViewProxy) {
        guard let id else { return }
        collapsed.subtract(tree.ancestors(of: id))
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id * 2, anchor: .center) }
        }
    }

    private func toggle(_ id: Int) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    private func setDescendants(of node: JSONNode, expanded: Bool) {
        var ids = Set<Int>()
        func walk(_ n: JSONNode) {
            if n.isContainer, !n.children.isEmpty { ids.insert(n.id) }
            n.children.forEach(walk)
        }
        walk(node)
        if expanded {
            collapsed.subtract(ids)
        } else {
            collapsed.formUnion(ids.subtracting([node.id]))
            collapsed.remove(node.id)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct JSONLineRow: View {
    enum SearchState { case none, match, current }

    let line: JSONTree.Line
    let isCollapsed: Bool
    let searchState: SearchState
    let onToggle: () -> Void
    let copy: () -> Void
    let setDescendants: (Bool) -> Void
    @State private var isHovering = false

    private static let indent: CGFloat = 16
    private var isToggleable: Bool { line.kind == .open || line.kind == .collapsed }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Color.clear.frame(width: CGFloat(line.node.depth) * Self.indent + 8, height: 1)
            Group {
                if isToggleable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                } else {
                    Text(" ")
                }
            }
            .frame(width: 14)
            // Long values wrap within their indentation instead of scrolling sideways.
            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture { if isToggleable { onToggle() } }
        .onHover { isHovering = $0 }
        .contextMenu {
            if line.kind != .close {
                Button(line.node.isContainer ? "Copy \(line.node.kind == .object ? "Object" : "Array")" : "Copy Value", action: copy)
            }
            if line.node.isContainer, !line.node.children.isEmpty {
                Divider()
                Button("Expand Children") { setDescendants(true) }
                Button("Collapse Children") { setDescendants(false) }
            }
        }
        .help(isToggleable ? (isCollapsed ? "Click to expand" : "Click to collapse") : "")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isToggleable ? .isButton : [])
        .accessibilityValue(isToggleable ? (isCollapsed ? "collapsed" : "expanded") : "")
    }

    private var background: Color {
        switch searchState {
        case .current: Color(nsColor: Theme.searchCurrent)
        case .match: Color(nsColor: Theme.searchMatch)
        case .none: isHovering ? Color.primary.opacity(0.05) : .clear
        }
    }

    private var content: AttributedString {
        let node = line.node
        var result = AttributedString()

        func add(_ text: String, _ color: Color) {
            var part = AttributedString(text)
            part.foregroundColor = color
            result += part
        }

        let open = node.kind == .object ? "{" : "["
        let close = node.kind == .object ? "}" : "]"

        if line.kind != .close, let key = node.rawKey {
            add(key, Color(nsColor: Theme.codeKey))
            add(": ", .secondary)
        }

        switch line.kind {
        case .value:
            switch node.kind {
            case .string: add(node.raw, Color(nsColor: Theme.codeString))
            case .number: add(node.raw, Color(nsColor: Theme.codeNumber))
            case .bool, .null: add(node.raw, Color(nsColor: Theme.codeLiteral))
            case .object, .array: add(open + close, .secondary)
            }
        case .open:
            add(open, .secondary)
        case .collapsed:
            add(open, .secondary)
            add(" … ", .secondary)
            add(close, .secondary)
            let count = node.children.count
            let noun = node.kind == .object ? (count == 1 ? "key" : "keys") : (count == 1 ? "item" : "items")
            add("  \(count) \(noun)", Color.secondary.opacity(0.7))
        case .close:
            add(close, .secondary)
        }
        if line.hasTrailingComma {
            // Keep the comma right after the value, before the item count.
            if line.kind == .collapsed, let range = result.range(of: close, options: .backwards) {
                var comma = AttributedString(",")
                comma.foregroundColor = .secondary
                result.insert(comma, at: range.upperBound)
            } else {
                add(",", .secondary)
            }
        }
        return result
    }
}
