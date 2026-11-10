import AppKit
import CourierCore
import SwiftUI

private enum ResponseSection: String, CaseIterable, Identifiable {
    case body, headers
    var id: String { rawValue }
}

enum BodyViewMode: String, Identifiable {
    case preview, pretty, raw
    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview: "Preview"
        case .pretty: "Pretty"
        case .raw: "Raw"
        }
    }

    func help(for format: ResponseFormat) -> String {
        switch (self, format) {
        case (.preview, .json): "Collapsible tree"
        case (.preview, _): "Rendered page (JavaScript off)"
        case (.pretty, _): "Formatted and highlighted"
        case (.raw, _): "Exactly as received"
        }
    }

    /// Modes that make sense for a response, best first.
    static func available(for response: HTTPResponse) -> [BodyViewMode] {
        var modes: [BodyViewMode] = []
        if response.jsonTree != nil || (response.format == .html && response.text != nil) { modes.append(.preview) }
        if response.prettyText != nil { modes.append(.pretty) }
        modes.append(.raw)
        return modes
    }
}

struct ResponsePanel: View {
    let tab: RequestTab
    @State private var section: ResponseSection = .body
    /// Last mode picked; falls back to the best available one when a response doesn't support it.
    @State private var preferredMode: BodyViewMode = .preview
    @State private var treeCommand = JSONTreeView.Command()

    // Search
    @State private var isSearching = false
    @State private var query = ""
    @State private var matchIndex = 0
    @State private var htmlFind = HTMLPreview.FindRequest()
    @State private var htmlFound: Bool?
    @FocusState private var isSearchFieldFocused: Bool

    /// What the search runs over in the current view, computed once per render.
    private struct SearchResults {
        var textRanges: [NSRange] = []
        var treeMatches: [Int] = []
        var headers: [KeyValue] = []
        /// Nil when the view can't count matches (HTML preview).
        var count: Int? = 0
        var isHTML = false
    }

    private func searchResults(for response: HTTPResponse) -> SearchResults {
        guard isSearching, !query.isEmpty else { return SearchResults(headers: response.headers) }
        switch section {
        case .headers:
            let rows = response.headers.filter {
                $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query)
            }
            return SearchResults(headers: rows, count: rows.count)
        case .body:
            switch mode(for: response) {
            case .preview:
                if let tree = response.jsonTree {
                    let matches = tree.matches(for: query)
                    return SearchResults(treeMatches: matches, headers: response.headers, count: matches.count)
                }
                return SearchResults(headers: response.headers, count: nil, isHTML: true)
            case .pretty, .raw:
                let ranges = TextSearch.ranges(of: query, in: displayText(for: response) ?? "")
                return SearchResults(textRanges: ranges, headers: response.headers, count: ranges.count)
            }
        }
    }

    private func currentIndex(_ results: SearchResults) -> Int? {
        guard let count = results.count, count > 0 else { return nil }
        return min(matchIndex, count - 1)
    }

    private func step(_ delta: Int, results: SearchResults) {
        if results.isHTML {
            htmlFind = HTMLPreview.FindRequest(id: htmlFind.id + 1, query: query, backwards: delta < 0)
            return
        }
        guard let count = results.count, count > 0 else { return }
        matchIndex = ((currentIndex(results) ?? 0) + delta + count) % count
    }

    /// The rendered HTML preview is on screen (its find runs inside WebKit).
    private var isShowingHTMLPreview: Bool {
        guard section == .body, let response = tab.response else { return false }
        return mode(for: response) == .preview && response.jsonTree == nil
    }

    private func openSearch() {
        isSearching = true
        isSearchFieldFocused = true
    }

    private func closeSearch() {
        isSearching = false
        isSearchFieldFocused = false
    }

    private func mode(for response: HTTPResponse) -> BodyViewMode {
        let modes = BodyViewMode.available(for: response)
        return modes.contains(preferredMode) ? preferredMode : modes[0]
    }

    var body: some View {
        let results = tab.response.map(searchResults(for:)) ?? SearchResults()
        VStack(spacing: 0) {
            header
            Divider()
            if isSearching, tab.response != nil, !tab.isLoading {
                searchBar(results)
                Divider()
            }
            content(results)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.content)
        .onChange(of: query) {
            matchIndex = 0
            htmlFound = nil
            if isShowingHTMLPreview {
                htmlFind = HTMLPreview.FindRequest(id: htmlFind.id + 1, query: query)
            }
        }
        // ⌘F opens search (unless you're editing the request body, which has its own find).
        // ⌘G / ⇧⌘G step through matches while it's open.
        .onLocalEvent(matching: .keyDown) { event in
            guard tab.response != nil else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased()
            if flags == .command, key == "f" {
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable, !editor.isFieldEditor {
                    return event
                }
                openSearch()
                return nil
            }
            if isSearching, key == "g", flags == .command || flags == [.command, .shift] {
                step(flags.contains(.shift) ? -1 : 1, results: results)
                return nil
            }
            return event
        }
    }

    private func searchBar(_ results: SearchResults) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(section == .headers ? "Filter headers" : "Find in response", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .onSubmit { step(1, results: results) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    step(-1, results: results)
                    return .handled
                }
                .onExitCommand { closeSearch() }
            if !query.isEmpty {
                Text(matchSummary(results))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if section == .body {
                ControlGroup {
                    Button { step(-1, results: results) } label: { Image(systemName: "chevron.up") }
                        .tooltip("Previous match (⇧⌘G)")
                        .accessibilityLabel("Previous match")
                    Button { step(1, results: results) } label: { Image(systemName: "chevron.down") }
                        .tooltip("Next match (⌘G)")
                        .accessibilityLabel("Next match")
                }
                .controlSize(.small)
                .fixedSize()
                .disabled(query.isEmpty || results.count == 0)
            }
            Button("Done") { closeSearch() }
                .controlSize(.small)
                .tooltip("Close search (Esc)")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func matchSummary(_ results: SearchResults) -> String {
        if results.isHTML {
            switch htmlFound {
            case true?: return "Found"
            case false?: return "No matches"
            case nil: return ""
            }
        }
        guard let count = results.count, count > 0 else { return "No matches" }
        if section == .headers { return count == 1 ? "1 header" : "\(count) headers" }
        let limitNote = count >= 10_000 ? "+" : ""
        return "\((currentIndex(results) ?? 0) + 1) of \(count)\(limitNote)"
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("Response").font(.headline)
            if let response = tab.response, !tab.isLoading {
                ResponseInfoBar(response: response)
                Spacer()
                TabSwitcher(selection: $section, items: [
                    .init(value: ResponseSection.body, title: "Body"),
                    .init(value: ResponseSection.headers, title: "Headers (\(response.headers.count))"),
                ])
                .accessibilityLabel("Response section")
                // Body controls stay in place on the Headers tab (disabled), so the bar doesn't jump.
                if response.format != .binary {
                    Group {
                        FormatBadge(response: response)
                            .opacity(section == .headers ? 0.5 : 1)
                        let modes = BodyViewMode.available(for: response)
                        if modes.count > 1 {
                            TabSwitcher(
                                selection: Binding(get: { mode(for: response) }, set: { preferredMode = $0 }),
                                items: modes.map { .init(value: $0, title: $0.title, help: $0.help(for: response.format)) }
                            )
                            .accessibilityLabel("Body view")
                        }
                    }
                    .disabled(section == .headers)
                }
                Button {
                    if isSearching { closeSearch() } else { openSearch() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .tooltip(isSearching ? "Close search" : "Find in response (⌘F)")
                .accessibilityLabel(isSearching ? "Close search" : "Find in response")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayText(for: response) ?? "", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .tooltip("Copy response body")
                .accessibilityLabel("Copy response body")
                .disabled(response.text == nil)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private var treeControls: some View {
        HStack(spacing: 2) {
            Button {
                treeCommand = JSONTreeView.Command(id: treeCommand.id + 1, expand: true)
            } label: {
                Image(systemName: "rectangle.expand.vertical").frame(width: 22, height: 20)
            }
            .tooltip("Expand all")
            .accessibilityLabel("Expand all")
            Divider().frame(height: 14)
            Button {
                treeCommand = JSONTreeView.Command(id: treeCommand.id + 1, expand: false)
            } label: {
                Image(systemName: "rectangle.compress.vertical").frame(width: 22, height: 20)
            }
            .tooltip("Collapse all")
            .accessibilityLabel("Collapse all")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator.opacity(0.6)))
        .padding(.top, 8)
        // Clear of the vertical scroller, which is up to ~16pt wide (hovered or "always show").
        .padding(.trailing, 20)
    }

    @ViewBuilder
    private func content(_ results: SearchResults) -> some View {
        if tab.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("Sending request…").foregroundStyle(.secondary)
            }
        } else if let error = tab.errorMessage {
            ContentUnavailableView {
                Label("Request Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error).textSelection(.enabled)
            }
        } else if let response = tab.response {
            switch section {
            case .body: bodyView(for: response, results: results)
            case .headers: HeadersList(headers: results.headers)
            }
        } else {
            ContentUnavailableView {
                Label("No Response Yet", systemImage: "paperplane")
            } description: {
                Text("Enter a URL and press ⌘↩ to send.\nPaste a cURL command into the URL field to import it.")
            }
        }
    }

    @ViewBuilder
    private func bodyView(for response: HTTPResponse, results: SearchResults) -> some View {
        if response.body.isEmpty {
            ContentUnavailableView("Empty Body", systemImage: "doc", description: Text("The server returned no content."))
        } else if response.contentType?.lowercased().hasPrefix("image/") == true, let image = NSImage(data: response.body) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image).padding()
            }
        } else if let text = response.text {
            switch mode(for: response) {
            case .preview:
                if let tree = response.jsonTree {
                    JSONTreeView(
                        tree: tree,
                        command: treeCommand,
                        searchMatches: results.treeMatches,
                        currentMatch: currentIndex(results).map { results.treeMatches[$0] }
                    )
                    .id(response.id)
                    // Floating over the tree so switching views doesn't shift the header controls.
                    .overlay(alignment: .topTrailing) { treeControls }
                } else {
                    HTMLPreview(html: text, baseURL: response.finalURL, find: htmlFind) { found in
                        htmlFound = found
                    }
                }
            case .pretty:
                CodeTextView(
                    text: .constant(response.prettyText ?? text), isEditable: false, language: CodeLanguage(response.format),
                    searchRanges: results.textRanges, currentSearchIndex: currentIndex(results)
                )
            case .raw:
                CodeTextView(
                    text: .constant(text), isEditable: false, language: CodeLanguage(response.format),
                    searchRanges: results.textRanges, currentSearchIndex: currentIndex(results)
                )
            }
        } else {
            ContentUnavailableView(
                "Binary Content",
                systemImage: "doc.zipper",
                description: Text("\(response.contentType ?? "Unknown type") · \(response.body.count) bytes")
            )
        }
    }

    /// What the copy button copies: raw in Raw mode, otherwise the formatted text.
    private func displayText(for response: HTTPResponse) -> String? {
        if mode(for: response) != .raw, let pretty = response.prettyText { return pretty }
        return response.text
    }
}

private struct FormatBadge: View {
    let response: HTTPResponse

    var body: some View {
        let isInvalid = response.format.isFormattable && response.prettyText == nil
        HStack(spacing: 4) {
            if isInvalid {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(response.format.title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().strokeBorder(Color.primary.opacity(0.15)))
        .help(isInvalid ? "Body isn't valid \(response.format.title)" : "Detected from \(response.contentType ?? "the body")")
        .accessibilityLabel(isInvalid ? "\(response.format.title), invalid" : response.format.title)
    }
}

private struct HeaderRow: View {
    let header: KeyValue
    let isStriped: Bool
    @State private var isHoveringValue = false
    @AppStorage(SettingsKey.maskSensitiveHeaders) private var maskSetting = true

    private var isMasked: Bool {
        maskSetting && !isHoveringValue && SensitiveHeaders.isSensitive(header.key)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(header.key)
                .fontWeight(.semibold)
                .frame(width: 240, alignment: .leading)
            Text(isMasked ? SensitiveHeaders.mask : header.value)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { isHoveringValue = $0 }
                .help(isMasked ? "Hidden because “\(header.key)” looks like a secret. Hover to show." : "")
        }
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isStriped ? Color.primary.opacity(0.03) : .clear)
    }
}

private struct HeadersList: View {
    let headers: [KeyValue]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.element.id) { index, header in
                    HeaderRow(header: header, isStriped: index.isMultiple(of: 2))
                }
            }
        }
    }
}
