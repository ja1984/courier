import AppKit
import CourierCore
import SwiftUI

@main
struct CourierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.system

    var body: some Scene {
        Window("Courier", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 940, minHeight: 600)
                .onChange(of: appearance, initial: true) { appearance.apply() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.saveTabs()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { CourierCommands(store: store) }

        Settings {
            SettingsView(store: store)
        }
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
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.system
    private static let recentLimit = 15

    /// Most recent first, one item per method + URL.
    private static func recentEntries(_ history: [HistoryEntry]) -> [HistoryEntry] {
        var seen = Set<String>()
        var result: [HistoryEntry] = []
        for entry in history where result.count < recentLimit {
            if seen.insert("\(entry.spec.method.rawValue) \(entry.spec.url)").inserted { result.append(entry) }
        }
        return result
    }

    /// "GET  api.example.com/users/42", shortened in the middle so the menu stays narrow.
    /// The query string is left out: it often carries tokens, and menus can't hide them.
    private static func menuTitle(for entry: HistoryEntry) -> String {
        var target = String(entry.spec.url.prefix { $0 != "?" && $0 != "#" })
        for scheme in ["https://", "http://"] where target.hasPrefix(scheme) {
            target.removeFirst(scheme.count)
        }
        if target.count > 70 { target = "\(target.prefix(45))…\(target.suffix(24))" }
        return "\(entry.spec.method.rawValue)  \(target)"
    }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Picker("Group History By", selection: $store.historyGrouping) {
                ForEach(HistoryGrouping.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        }
        CommandMenu("History") {
            Button("Reopen Closed Tab") { store.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(store.closedTabs.isEmpty)
            Section("Recent Requests") {
                if store.history.isEmpty {
                    Text("No Requests Yet")
                }
                ForEach(Self.recentEntries(store.history)) { entry in
                    Button(Self.menuTitle(for: entry)) { store.open(entry.spec) }
                }
            }
            Divider()
            Button("Clear History…") { store.isConfirmingClearHistory = true }
                .disabled(store.history.isEmpty)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { store.newTab() }
                .keyboardShortcut("t")
            Button("Close Tab") { store.closeSelectedTab() }
                .keyboardShortcut("w")
            Divider()
            Button("Save") { store.saveSelected() }
                .keyboardShortcut("s")
                .disabled(store.selectedTab == nil || store.selectedTab?.savedRequestID != nil && store.selectedTab?.hasUnsavedChanges == false)
            Button("Save As…") { store.saveSelectedAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(store.selectedTab == nil)
            Divider()
            Button("Import cURL from Clipboard") { store.importCurlFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button("Import Collections…") { store.importCollections() }
            Button("Export All Collections…") { store.exportCollections() }
                .disabled(store.library.isEmpty)
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
