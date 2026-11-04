import CourierCore
import SwiftUI

/// Saved requests, grouped by collection.
struct CollectionsList: View {
    let store: AppStore
    let search: String
    @State private var collapsed: Set<UUID> = []
    @State private var renaming: RenameTarget?
    @State private var renameText = ""
    @State private var collectionToDelete: RequestCollection?

    private enum RenameTarget: Equatable {
        case collection(UUID)
        case request(UUID)
    }

    private var collections: [RequestCollection] { store.library.filtered(by: search) }
    private var openRequestID: UUID? { store.selectedTab?.savedRequestID }

    private func isExpanded(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { !search.trimmingCharacters(in: .whitespaces).isEmpty || !collapsed.contains(id) },
            set: { expanded in
                if expanded { collapsed.remove(id) } else { collapsed.insert(id) }
            }
        )
    }

    var body: some View {
        Group {
            if store.library.isEmpty {
                ContentUnavailableView {
                    Label("No Saved Requests", systemImage: "folder")
                } description: {
                    Text("Save a request with ⌘S to keep it here. Saved requests are never removed automatically.")
                } actions: {
                    Button("Save Current Request…") { store.saveSelectedAs() }
                        .disabled(store.selectedTab?.spec.url.isEmpty ?? true)
                    Button("Import Collections…") { store.importCollections() }
                        .buttonStyle(.link)
                }
            } else if collections.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    ForEach(collections) { collection in
                        Section(isExpanded: isExpanded(collection.id)) {
                            if collection.requests.isEmpty {
                                Text("Empty. Save a request here with ⌘S.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            ForEach(collection.requests) { request in
                                requestRow(request)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                CollectionMark(color: collection.color)
                                Text(collection.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(collection.requests.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                    .padding(.trailing, 8)
                            }
                            .help(collection.name)
                            .contextMenu {
                                Button("Rename…") { startRename(.collection(collection.id), current: collection.name) }
                                Button("Export…") { store.exportCollections([collection.id]) }
                                Picker("Color", selection: Binding(
                                    get: { collection.color },
                                    set: { store.setCollectionColor($0, for: collection.id) }
                                )) {
                                    Text("None").tag(CollectionColor?.none)
                                    Divider()
                                    ForEach(CollectionColor.allCases) { color in
                                        Label { Text(color.title) } icon: { Image(nsImage: color.swatch) }
                                            .tag(Optional(color))
                                    }
                                }
                                Divider()
                                Button("Delete Collection…", role: .destructive) {
                                    if collection.requests.isEmpty {
                                        store.deleteCollection(collection.id)
                                    } else {
                                        collectionToDelete = collection
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                switch renaming {
                case .collection(let id): store.renameCollection(id, to: renameText)
                case .request(let id): store.renameSavedRequest(id, to: renameText)
                case nil: break
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete “\(collectionToDelete?.name ?? "")”?",
            isPresented: Binding(get: { collectionToDelete != nil }, set: { if !$0 { collectionToDelete = nil } }),
            presenting: collectionToDelete
        ) { collection in
            Button("Delete Collection", role: .destructive) { store.deleteCollection(collection.id) }
        } message: { collection in
            Text("This deletes the collection and its \(collection.requests.count) saved requests. It can't be undone. Open tabs keep their contents.")
        }
    }

    private func requestRow(_ request: SavedRequest) -> some View {
        Button {
            store.openSaved(request.id)
        } label: {
            SavedRequestRow(request: request)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            request.id == openRequestID
                ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor.opacity(0.14)).padding(.horizontal, 8)
                : nil
        )
        .contextMenu {
            Button("Open in New Tab") { store.openSaved(request.id, inNewTab: true) }
            Button("Rename…") { startRename(.request(request.id), current: request.name) }
            Button("Duplicate") { store.duplicateSavedRequest(request.id) }
            Button("Copy as cURL") { store.copyAsCurl(request.spec) }
            Divider()
            Button("Delete", role: .destructive) { store.deleteSavedRequest(request.id) }
        }
    }

    private func startRename(_ target: RenameTarget, current: String) {
        renameText = current
        renaming = target
    }
}

private struct SavedRequestRow: View {
    let request: SavedRequest

    var body: some View {
        HStack(spacing: 8) {
            MethodLabel(method: request.spec.method)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(request.spec.hostLabel ?? request.spec.url)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help("\(request.spec.method.rawValue) \(request.spec.url)\nClick to open · Right-click for more")
    }
}
