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

    /// The saved request this tab edits, if any; ⌘S updates it.
    var savedRequestID: UUID?
    /// Name and contents of that saved request, to show the name and detect unsaved changes.
    var savedName: String?
    var savedSpec: RequestSpec?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestToken = UUID()

    init(id: UUID = UUID(), spec: RequestSpec = RequestSpec()) {
        self.id = id
        self.spec = spec
    }

    /// Linked to a saved request and edited since it was saved or opened.
    var hasUnsavedChanges: Bool {
        guard savedRequestID != nil, let savedSpec else { return false }
        return !spec.hasSameContent(as: savedSpec)
    }

    func link(to request: SavedRequest) {
        savedRequestID = request.id
        savedName = request.name
        savedSpec = request.spec
    }

    func unlink() {
        savedRequestID = nil
        savedName = nil
        savedSpec = nil
    }

    var title: String {
        if let savedName { return savedName }
        let summary = spec.urlSummary
        if spec.url.trimmingCharacters(in: .whitespaces).isEmpty { return "New Request" }
        if summary.path.isEmpty || summary.path == "/" { return summary.host ?? spec.url }
        return summary.path
    }

    /// A fresh tab that can be reused instead of opening another one.
    var isPristine: Bool {
        spec == RequestSpec() && response == nil && errorMessage == nil && !isLoading && savedRequestID == nil
    }

    /// URL edits from the address field. A pasted cURL command replaces the whole request.
    func updateURL(_ newValue: String) {
        // Text fields write their value back when they lose focus; that's not an edit.
        guard newValue != spec.url else { return }
        let isPaste = newValue.count - spec.url.count > 1
        if isPaste, CurlParser.looksLikeCurl(newValue), let parsed = try? CurlParser.parse(newValue) {
            spec = parsed
            return
        }
        spec.setURL(newValue)
    }

    /// `onFinish` gets the history entry and the cookies the response set.
    func send(jar: CookieJar?, onFinish: @escaping (HistoryEntry, [StoredCookie]) -> Void) {
        task?.cancel()
        let token = UUID()
        requestToken = token
        let spec = spec
        isLoading = true
        errorMessage = nil

        task = Task { [weak self] in
            let started = Date()
            do {
                let response = try await HTTPClient.send(spec, jar: jar)
                guard let self, self.requestToken == token else { return }
                self.response = response
                self.isLoading = false
                onFinish(
                    HistoryEntry(date: started, spec: spec, statusCode: response.statusCode, durationMs: response.durationMs),
                    response.receivedCookies
                )
            } catch {
                guard let self, self.requestToken == token else { return }
                self.isLoading = false
                guard !Self.isCancellation(error) else { return }
                self.response = nil
                self.errorMessage = error.localizedDescription
                onFinish(HistoryEntry(date: started, spec: spec, errorMessage: error.localizedDescription), [])
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

/// A pending "save to collection" sheet for a tab.
struct SaveRequestTarget: Identifiable {
    let tabID: UUID
    var id: UUID { tabID }
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
    var library: CollectionLibrary
    /// Cookies remembered from responses (when "Remember cookies" is on in Settings).
    var cookieJar: CookieJar
    var alert: AppAlert?
    var saveRequestTarget: SaveRequestTarget?
    /// Preselected in the save sheet: the collection used last.
    var lastCollectionID: UUID?
    /// Shared by the sidebar menu and the History menu bar item.
    var isConfirmingClearHistory = false

    private static let groupingKey = "historyGrouping"
    var historyGrouping: HistoryGrouping = HistoryGrouping(
        rawValue: UserDefaults.standard.string(forKey: AppStore.groupingKey) ?? ""
    ) ?? .date {
        didSet { UserDefaults.standard.set(historyGrouping.rawValue, forKey: Self.groupingKey) }
    }

    /// Internal (not private) so CollectionFiles.swift can save imports.
    @ObservationIgnored let persistence: Persistence
    static let historyLimit = 500

    init(persistence: Persistence = Persistence()) {
        self.persistence = persistence
        history = persistence.loadHistory()
        let library = persistence.loadCollections()
        self.library = library
        var jar = persistence.loadCookies()
        jar.removeExpired()
        cookieJar = jar
        let snapshot = persistence.loadTabs()
        tabs = snapshot?.tabs.map { saved in
            let tab = RequestTab(id: saved.id, spec: saved.spec)
            if let id = saved.savedRequestID, let request = library.request(id)?.request {
                // Keep the tab's own (possibly unsaved) edits; compare against the saved version.
                tab.savedRequestID = id
                tab.savedName = request.name
                tab.savedSpec = request.spec
            }
            return tab
        } ?? []
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

    /// Recently closed tabs, newest last, for Reopen Closed Tab (⇧⌘T). Kept for this session only.
    private(set) var closedTabs: [ClosedTab] = []
    static let closedTabsLimit = 25

    struct ClosedTab {
        let spec: RequestSpec
        let index: Int
        let savedRequestID: UUID?
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[index]
        closing.cancel()
        if !closing.isPristine {
            closedTabs.append(ClosedTab(spec: closing.spec, index: index, savedRequestID: closing.savedRequestID))
            if closedTabs.count > Self.closedTabsLimit { closedTabs.removeFirst() }
        }
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

    /// Reopens the most recently closed tab where it was. Replaces the tab
    /// if it's the only one and still blank (e.g. after closing the last tab).
    func reopenClosedTab() {
        guard let closed = closedTabs.popLast() else { return }
        let tab = RequestTab(spec: closed.spec)
        if let id = closed.savedRequestID, let request = library.request(id)?.request {
            tab.link(to: request)
            tab.spec = closed.spec // keep edits that weren't saved before closing
        }
        if tabs.count == 1, tabs[0].isPristine {
            tabs = [tab]
        } else {
            tabs.insert(tab, at: min(closed.index, tabs.count))
        }
        selectedTabID = tab.id
        saveTabs()
    }

    func closeSelectedTab() {
        if let selectedTabID { closeTab(selectedTabID) }
    }

    // MARK: Collections

    /// ⌘S: updates the linked saved request, or asks where to save a new one.
    func saveSelected() {
        guard let tab = selectedTab else { return }
        if let id = tab.savedRequestID, library.request(id) != nil {
            library.updateRequest(id, spec: tab.spec)
            tab.savedSpec = tab.spec
            persistence.saveCollections(library)
        } else {
            tab.unlink()
            saveRequestTarget = SaveRequestTarget(tabID: tab.id)
        }
    }

    /// ⇧⌘S: always saves a new copy.
    func saveSelectedAs() {
        guard let tab = selectedTab else { return }
        saveRequestTarget = SaveRequestTarget(tabID: tab.id)
    }

    /// Saves a tab as a new request, into an existing collection or a new one, and links the tab to it.
    func saveTab(_ tabID: UUID, name: String, collectionID: UUID?, newCollectionName: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        let target = collectionID.flatMap { library.collection($0)?.id } ?? library.addCollection(named: newCollectionName)
        guard let id = library.saveRequest(tab.spec, named: name, in: target),
              let request = library.request(id)?.request
        else { return }
        tab.link(to: request)
        lastCollectionID = target
        persistence.saveCollections(library)
        saveTabs()
    }

    /// Opens a saved request: switches to a tab that already has it, else reuses a blank tab or opens one.
    func openSaved(_ id: UUID, inNewTab: Bool = false) {
        guard let request = library.request(id)?.request else { return }
        if !inNewTab, let existing = tabs.first(where: { $0.savedRequestID == id }) {
            selectedTabID = existing.id
            scheduleTabsSave()
            return
        }
        let tab: RequestTab
        if !inNewTab, let current = selectedTab, current.isPristine {
            tab = current
            tab.spec = request.spec
        } else {
            tab = RequestTab(spec: request.spec)
            tabs.append(tab)
            selectedTabID = tab.id
        }
        tab.link(to: request)
        saveTabs()
    }

    func addCollection(named name: String) {
        lastCollectionID = library.addCollection(named: name)
        persistence.saveCollections(library)
    }

    func renameCollection(_ id: UUID, to name: String) {
        library.renameCollection(id, to: name)
        persistence.saveCollections(library)
    }

    /// Deletes a collection and its requests. Open tabs keep their contents but are no longer linked.
    func setCollectionColor(_ color: CollectionColor?, for id: UUID) {
        library.setColor(color, for: id)
        persistence.saveCollections(library)
    }

    /// The collection a tab's saved request belongs to, if it's linked.
    func collection(for tab: RequestTab) -> RequestCollection? {
        tab.savedRequestID.flatMap { library.request($0)?.collection }
    }

    func deleteCollection(_ id: UUID) {
        let requestIDs = Set(library.collection(id)?.requests.map(\.id) ?? [])
        library.deleteCollection(id)
        for tab in tabs where tab.savedRequestID.map(requestIDs.contains) == true { tab.unlink() }
        if lastCollectionID == id { lastCollectionID = nil }
        persistence.saveCollections(library)
        saveTabs()
    }

    func renameSavedRequest(_ id: UUID, to name: String) {
        library.renameRequest(id, to: name)
        let newName = library.request(id)?.request.name
        for tab in tabs where tab.savedRequestID == id { tab.savedName = newName }
        persistence.saveCollections(library)
    }

    func duplicateSavedRequest(_ id: UUID) {
        library.duplicateRequest(id)
        persistence.saveCollections(library)
    }

    func deleteSavedRequest(_ id: UUID) {
        library.deleteRequest(id)
        for tab in tabs where tab.savedRequestID == id { tab.unlink() }
        persistence.saveCollections(library)
        saveTabs()
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
        let remember = rememberCookies
        tab.send(jar: remember ? cookieJar : nil) { [weak self] entry, cookies in
            self?.record(entry)
            if remember { self?.storeCookies(cookies) }
        }
        saveTabs()
    }

    // MARK: Cookies

    /// On unless turned off in Settings.
    var rememberCookies: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.rememberCookies) as? Bool ?? true
    }

    private func storeCookies(_ cookies: [StoredCookie]) {
        guard !cookies.isEmpty else { return }
        cookieJar.store(cookies)
        persistence.saveCookies(cookieJar)
    }

    func setCookieValue(_ value: String, for id: StoredCookie.ID) {
        cookieJar.setValue(value, for: id)
        persistence.saveCookies(cookieJar)
    }

    func deleteCookie(_ id: StoredCookie.ID) {
        cookieJar.remove(id)
        persistence.saveCookies(cookieJar)
    }

    func clearCookies(domain: String) {
        cookieJar.removeAll(domain: domain)
        persistence.saveCookies(cookieJar)
    }

    func clearAllCookies() {
        cookieJar.removeAll()
        persistence.saveCookies(cookieJar)
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
            tabs: tabs.map { TabsSnapshot.Tab(id: $0.id, spec: $0.spec, savedRequestID: $0.savedRequestID) },
            selectedID: selectedTabID
        ))
    }
}
