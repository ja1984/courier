import AppKit
import CourierCore
import SwiftUI

@main
struct CourierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        Window("Courier", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 940, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.saveTabs()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { CourierCommands(store: store) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than a .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct CourierCommands: Commands {
    @Bindable var store: AppStore

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Picker("Group History By", selection: $store.historyGrouping) {
                ForEach(HistoryGrouping.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        }
        CommandMenu("History") {
            Button("Clear History…") { store.isConfirmingClearHistory = true }
                .disabled(store.history.isEmpty)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { store.newTab() }
                .keyboardShortcut("t")
            Button("Close Tab") { store.closeSelectedTab() }
                .keyboardShortcut("w")
            Divider()
            Button("Import cURL from Clipboard") { store.importCurlFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        CommandMenu("Request") {
            Button("Send") { store.sendSelected() }
                .keyboardShortcut(.return)
                .disabled(store.selectedTab?.spec.url.isEmpty ?? true)
            Button("Cancel") { store.selectedTab?.cancel() }
                .keyboardShortcut(".")
                .disabled(!(store.selectedTab?.isLoading ?? false))
            Divider()
            Button("Copy as cURL") {
                if let spec = store.selectedTab?.spec { store.copyAsCurl(spec) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Button("Next Tab") { store.selectTab(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { store.selectTab(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}
