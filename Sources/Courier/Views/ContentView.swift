import CourierCore
import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationSplitView {
            HistorySidebar(store: store)
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
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            MethodLabel(method: tab.spec.method)
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            if tab.isLoading {
                ProgressView().controlSize(.mini)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help("Close tab (⌘W)")
            .accessibilityLabel("Close tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
        .help(tab.spec.url.isEmpty ? "Middle-click to close" : "\(tab.spec.url)\nMiddle-click to close")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: "Close", onClose)
    }
}
