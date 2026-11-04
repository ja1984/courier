import AppKit
import CourierCore
import Observation

@Observable
final class RequestTab: Identifiable {
    let id: UUID
    var spec: RequestSpec
    var response: HTTPResponse?
    var errorMessage: String?
    var isLoading = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestToken = UUID()

    init(id: UUID = UUID(), spec: RequestSpec = RequestSpec()) {
        self.id = id
        self.spec = spec
    }

    var title: String {
        let summary = spec.urlSummary
        if spec.url.trimmingCharacters(in: .whitespaces).isEmpty { return "New Request" }
        if summary.path.isEmpty || summary.path == "/" { return summary.host ?? spec.url }
        return summary.path
    }

    /// A fresh tab that can be reused instead of opening another one.
    var isPristine: Bool {
        spec == RequestSpec() && response == nil && errorMessage == nil && !isLoading
    }

    /// URL edits from the address field. A pasted cURL command replaces the whole request.
    func updateURL(_ newValue: String) {
        let isPaste = newValue.count - spec.url.count > 1
        if isPaste, CurlParser.looksLikeCurl(newValue), let parsed = try? CurlParser.parse(newValue) {
            spec = parsed
            return
        }
        spec.setURL(newValue)
    }

    func send(onFinish: @escaping (HistoryEntry) -> Void) {
        task?.cancel()
        let token = UUID()
        requestToken = token
        let spec = spec
        isLoading = true
        errorMessage = nil

        task = Task { [weak self] in
            let started = Date()
            do {
                let response = try await HTTPClient.send(spec)
                guard let self, self.requestToken == token else { return }
                self.response = response
                self.isLoading = false
                onFinish(HistoryEntry(date: started, spec: spec, statusCode: response.statusCode, durationMs: response.durationMs))
            } catch {
                guard let self, self.requestToken == token else { return }
                self.isLoading = false
                guard !Self.isCancellation(error) else { return }
                self.response = nil
                self.errorMessage = error.localizedDescription
                onFinish(HistoryEntry(date: started, spec: spec, errorMessage: error.localizedDescription))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        requestToken = UUID()
        isLoading = false
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@Observable
final class AppStore {
    var tabs: [RequestTab]
    var selectedTabID: UUID?
    var history: [HistoryEntry]
    var alert: AppAlert?
    /// Shared by the sidebar menu and the History menu bar item.
    var isConfirmingClearHistory = false

    private static let groupingKey = "historyGrouping"
    var historyGrouping: HistoryGrouping = HistoryGrouping(
        rawValue: UserDefaults.standard.string(forKey: AppStore.groupingKey) ?? ""
    ) ?? .date {
        didSet { UserDefaults.standard.set(historyGrouping.rawValue, forKey: Self.groupingKey) }
    }

    @ObservationIgnored private let persistence: Persistence
    static let historyLimit = 500

    init(persistence: Persistence = Persistence()) {
        self.persistence = persistence
        history = persistence.loadHistory()
        let snapshot = persistence.loadTabs()
        tabs = snapshot?.tabs.map { RequestTab(id: $0.id, spec: $0.spec) } ?? []
        if tabs.isEmpty { tabs = [RequestTab()] }
        selectedTabID = tabs.contains { $0.id == snapshot?.selectedID } ? snapshot?.selectedID : tabs.first?.id

        if let reason = persistence.unavailableReason {
            alert = AppAlert(
                title: "Tabs and history won't be saved",
                message: "\(reason) Nothing is written to disk this session, so nothing is stored unencrypted."
            )
        } else if persistence.hasLegacyPlaintext {
            // Re-save files from older versions encrypted; this also deletes the plaintext copies.
            persistence.saveHistory(history)
            saveTabs()
        }
    }

    var selectedTab: RequestTab? {
        tabs.first { $0.id == selectedTabID }
    }

    // MARK: Tabs

    func newTab(spec: RequestSpec = RequestSpec()) {
        let tab = RequestTab(spec: spec)
        tabs.append(tab)
        selectedTabID = tab.id
        saveTabs()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].cancel()
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab()
            return
        }
        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        saveTabs()
    }

    func closeSelectedTab() {
        if let selectedTabID { closeTab(selectedTabID) }
    }

    func selectTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }), !tabs.isEmpty else { return }
        selectedTabID = tabs[(index + offset + tabs.count) % tabs.count].id
        scheduleTabsSave()
    }

    /// Opens a request, reusing the current tab if it's still blank.
    func open(_ spec: RequestSpec) {
        if let current = selectedTab, current.isPristine {
            current.spec = spec
            saveTabs()
        } else {
            newTab(spec: spec)
        }
    }

    // MARK: Requests

    func send(_ tab: RequestTab) {
        guard !tab.spec.url.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        tab.send { [weak self] entry in self?.record(entry) }
        saveTabs()
    }

    func sendSelected() {
        if let selectedTab { send(selectedTab) }
    }

    func importCurl(_ text: String) {
        do {
            open(try CurlParser.parse(text))
        } catch {
            alert = AppAlert(title: "Couldn't import cURL", message: error.localizedDescription)
        }
    }

    func importCurlFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            alert = AppAlert(title: "Clipboard is empty", message: "Copy a cURL command first, then try again.")
            return
        }
        importCurl(text)
    }

    func copyAsCurl(_ spec: RequestSpec) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CurlExporter.command(for: spec), forType: .string)
    }

    // MARK: History

    private func record(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        persistence.saveHistory(history)
    }

    func deleteHistory(_ id: UUID) {
        history.removeAll { $0.id == id }
        persistence.saveHistory(history)
    }

    func clearHistory() {
        history = []
        persistence.saveHistory(history)
    }

    // MARK: Persistence

    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// Debounced save for edits, so typing doesn't write to disk on every keystroke
    /// but a crash or force-quit loses at most about a second of changes.
    func scheduleTabsSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveTabs()
        }
    }

    func saveTabs() {
        pendingSave?.cancel()
        pendingSave = nil
        persistence.saveTabs(TabsSnapshot(
            tabs: tabs.map { TabsSnapshot.Tab(id: $0.id, spec: $0.spec) },
            selectedID: selectedTabID
        ))
    }
}
