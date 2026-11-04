import CourierCore
import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    /// "Github · Courier" for a saved request, else the URL of the open request.
    private var windowSubtitle: String {
        guard let tab = store.selectedTab else { return "" }
        if let collection = store.collection(for: tab), let name = tab.savedName {
            return "\(collection.name) · \(name)"
        }
        return tab.spec.url
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            VStack(spacing: 0) {
                TabBar(store: store)
                Divider()
                if let tab = store.selectedTab {
                    RequestWorkspace(tab: tab, store: store)
                        .id(tab.id)
                }
            }
            .background(Theme.content)
            .navigationTitle("Courier")
            .navigationSubtitle(windowSubtitle)
        }
        .alert(
            store.alert?.title ?? "",
            isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } }),
            presenting: store.alert
        ) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
        .sheet(item: $store.saveRequestTarget) { target in
            if let tab = store.tabs.first(where: { $0.id == target.tabID }) {
                SaveRequestSheet(store: store, tab: tab)
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $store.isConfirmingClearHistory) {
            Button("Clear History", role: .destructive) { store.clearHistory() }
        } message: {
            Text("This removes all \(store.history.count) saved requests. It can't be undone.")
        }
        // ⌘V with a cURL command on the clipboard opens it as a request, wherever focus is.
        // Anything else pastes normally.
        .onLocalEvent(matching: .keyDown) { [store] event in
            let isCommandV = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                && event.charactersIgnoringModifiers?.lowercased() == "v"
            guard isCommandV,
                  let text = NSPasteboard.general.string(forType: .string),
                  CurlParser.looksLikeCurl(text)
            else { return event }
            store.importCurl(text)
            return nil
        }
    }
}

struct TabBar: View {
    let store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(store.tabs) { tab in
                            TabChip(
                                tab: tab,
                                collection: store.collection(for: tab),
                                isSelected: tab.id == store.selectedTabID,
                                onSelect: {
                                    store.selectedTabID = tab.id
                                    store.scheduleTabsSave()
                                },
                                onClose: { store.closeTab(tab.id) },
                                onHoverChange: { hovering in
                                    if hovering {
                                        hoverTracker.tabID = tab.id
                                    } else if hoverTracker.tabID == tab.id {
                                        hoverTracker.tabID = nil
                                    }
                                }
                            )
                            .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: store.selectedTabID) { _, id in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
            Divider().frame(height: 18)
            Button {
                store.newTab()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
            .help("New Tab (⌘T)")
            .accessibilityLabel("New Tab")
        }
        .background(Theme.content)
        // SwiftUI has no middle-click gesture, so watch for it app-wide and
        // close whichever tab the pointer is over.
        .onLocalEvent(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2, let id = hoverTracker.tabID else { return event }
            hoverTracker.tabID = nil
            store.closeTab(id)
            return nil
        }
    }

    /// The tab under the pointer. A reference type so the event monitor always reads the current value.
    private final class HoverTracker {
        var tabID: UUID?
    }

    @State private var hoverTracker = HoverTracker()
}

private struct TabChip: View {
    let tab: RequestTab
    /// The collection this tab's saved request is in, if it's linked to one.
    let collection: RequestCollection?
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void
    @State private var isHovering = false

    private var tabHelp: String {
        var lines: [String] = []
        if !tab.spec.url.isEmpty { lines.append(tab.spec.url) }
        if let collection { lines.append("Saved in “\(collection.name)”") }
        lines.append("Middle-click to close")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 6) {
            if let collection {
                // Saved in a collection: a dot in its color (gray when it has none).
                Circle()
                    .fill(collection.color.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.tertiary))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            MethodLabel(method: tab.spec.method)
            Text(tab.title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if tab.isLoading {
                ProgressView().controlSize(.mini)
            }
            Button(action: onClose) {
                Group {
                    // Like an editor: unsaved changes show as a dot that turns into the close button on hover.
                    if tab.hasUnsavedChanges && !isHovering {
                        Circle().frame(width: 7, height: 7)
                    } else {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                }
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .opacity(isHovering || isSelected || tab.hasUnsavedChanges ? 1 : 0)
            .help(tab.hasUnsavedChanges ? "Unsaved changes. Press ⌘S to save · Close tab (⌘W)" : "Close tab (⌘W)")
            .accessibilityLabel("Close tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: 220)
        // Same soft pill as the other tabs in the app (Keychain Access style).
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.09 : (isHovering ? 0.05 : 0)))
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
        .help(tabHelp)
        .accessibilityElement(children: .combine)
        .accessibilityValue([
            collection.map { "In \($0.name)" },
            tab.hasUnsavedChanges ? "Unsaved changes" : nil,
        ].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: "Close", onClose)
    }
}
