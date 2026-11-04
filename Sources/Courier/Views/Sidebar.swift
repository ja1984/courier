import CourierCore
import SwiftUI

enum SidebarMode: String, CaseIterable, Identifiable {
    case history, collections

    var id: String { rawValue }
    var title: String {
        switch self {
        case .history: "History"
        case .collections: "Collections"
        }
    }
}

/// History | Collections, sharing one search field.
struct Sidebar: View {
    @Bindable var store: AppStore
    @AppStorage("sidebarMode") private var mode = SidebarMode.history
    @State private var search = ""
    @State private var isAddingCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        VStack(spacing: 0) {
            TabSwitcher(
                selection: $mode,
                items: SidebarMode.allCases.map { TabSwitcher.Item(value: $0, title: $0.title) }
            )
            .accessibilityLabel("Sidebar")
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Group {
                switch mode {
                case .collections: CollectionsList(store: store, search: search)
                case .history: HistoryList(store: store, search: search)
                }
            }
            // Fill the column so the switch stays at the top, also above empty states.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $search, placement: .sidebar, prompt: mode == .history ? "Search history" : "Search collections")
        .toolbar {
            ToolbarItem {
                Menu {
                    switch mode {
                    case .collections:
                        Button("New Collection…") {
                            newCollectionName = ""
                            isAddingCollection = true
                        }
                        Button("Save Current Request…") { store.saveSelectedAs() }
                            .disabled(store.selectedTab == nil)
                        Divider()
                        Button("Import…") { store.importCollections() }
                        Button("Export All…") { store.exportCollections() }
                            .disabled(store.library.isEmpty)
                    case .history:
                        Picker("Group By", selection: $store.historyGrouping) {
                            ForEach(HistoryGrouping.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                        Divider()
                        Button("Clear History…", role: .destructive) { store.isConfirmingClearHistory = true }
                            .disabled(store.history.isEmpty)
                    }
                } label: {
                    Label("\(mode.title) Options", systemImage: "ellipsis")
                }
                .help("\(mode.title) options")
            }
        }
        .alert("New Collection", isPresented: $isAddingCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Create") { store.addCollection(named: newCollectionName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct HistoryList: View {
    @Bindable var store: AppStore
    let search: String
    @State private var collapsedGroups: Set<String> = []

    private var grouping: HistoryGrouping { store.historyGrouping }

    private var filtered: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.history }
        return store.history.filter {
            $0.spec.url.localizedCaseInsensitiveContains(query)
                || $0.spec.method.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private func isExpanded(_ groupID: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(groupID) },
            set: { expanded in
                if expanded { collapsedGroups.remove(groupID) } else { collapsedGroups.insert(groupID) }
            }
        )
    }

    var body: some View {
        Group {
            if store.history.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Requests you send will show up here.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    ForEach(grouping.groups(for: filtered)) { group in
                        Section(isExpanded: isExpanded(group.id)) {
                            ForEach(group.entries) { entry in
                                Button {
                                    store.open(entry.spec)
                                } label: {
                                    HistoryRow(entry: entry, grouping: grouping)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Open in New Tab") { store.newTab(spec: entry.spec) }
                                    Button("Save to Collection…") {
                                        store.open(entry.spec)
                                        store.saveSelectedAs()
                                    }
                                    Button("Copy as cURL") { store.copyAsCurl(entry.spec) }
                                    Divider()
                                    Button("Delete", role: .destructive) { store.deleteHistory(entry.id) }
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.title).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(group.entries.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                    .padding(.trailing, 8)
                            }
                            .help(group.title)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let grouping: HistoryGrouping

    private var subtitle: String {
        switch grouping {
        // Grouped by date: the host tells requests apart.
        case .date: entry.spec.hostLabel ?? entry.spec.url
        // Grouped by host: the date is what's missing.
        case .host: entry.date.formatted(.relative(presentation: .named))
        }
    }

    var body: some View {
        let path = entry.spec.urlSummary.path
        HStack(spacing: 8) {
            MethodLabel(method: entry.spec.method)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(path.isEmpty ? "/" : path)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.statusCode.map(String.init) ?? "ERR")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StatusStyle.color(for: entry.statusCode))
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help(tooltip)
    }

    private var tooltip: String {
        var lines = ["\(entry.spec.method.rawValue) \(entry.spec.url)"]
        if let error = entry.errorMessage { lines.append(error) }
        lines.append("Click to open · Right-click for more")
        return lines.joined(separator: "\n")
    }
}
