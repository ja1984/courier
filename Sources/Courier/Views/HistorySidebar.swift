import CourierCore
import SwiftUI

struct HistorySidebar: View {
    @Bindable var store: AppStore
    @State private var search = ""
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
                            }
                            .help(group.title)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search history")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Group By", selection: $store.historyGrouping) {
                        ForEach(HistoryGrouping.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Clear History…", role: .destructive) { store.isConfirmingClearHistory = true }
                        .disabled(store.history.isEmpty)
                } label: {
                    Label("History Options", systemImage: "ellipsis")
                }
                .help("History options")
            }
        }
        .navigationTitle("History")
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
