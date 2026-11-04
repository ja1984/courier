import CourierCore
import SwiftUI

/// Asks for a name and a collection, then saves the tab's request there.
struct SaveRequestSheet: View {
    let store: AppStore
    let tab: RequestTab
    @Environment(\.dismiss) private var dismiss

    /// nil means "New Collection".
    @State private var collectionID: UUID?
    @State private var name = ""
    @State private var newCollectionName = ""
    @FocusState private var nameIsFocused: Bool

    private var collections: [RequestCollection] { store.library.collections }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Request").font(.headline)

            Form {
                TextField("Name", text: $name, prompt: Text(CollectionLibrary.suggestedName(for: tab.spec)))
                    .focused($nameIsFocused)
                Picker("Collection", selection: $collectionID) {
                    ForEach(collections) { collection in
                        Text(collection.name).tag(Optional(collection.id))
                    }
                    if !collections.isEmpty { Divider() }
                    Text("New Collection…").tag(UUID?.none)
                }
                if collectionID == nil {
                    TextField(
                        "New collection",
                        text: $newCollectionName,
                        prompt: Text(CollectionLibrary.suggestedCollectionName(for: tab.spec))
                    )
                }
            }
            .formStyle(.columns)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.saveTab(
                        tab.id,
                        name: name,
                        collectionID: collectionID,
                        newCollectionName: newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? CollectionLibrary.suggestedCollectionName(for: tab.spec)
                            : newCollectionName
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            name = tab.savedName ?? ""
            collectionID = store.lastCollectionID.flatMap { store.library.collection($0)?.id }
                ?? collections.first { $0.name == CollectionLibrary.suggestedCollectionName(for: tab.spec) }?.id
                ?? collections.first?.id
            nameIsFocused = true
        }
    }
}
