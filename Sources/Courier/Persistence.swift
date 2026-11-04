import CourierCore
import Foundation
import os

nonisolated struct TabsSnapshot: Codable {
    struct Tab: Codable {
        var id: UUID
        var spec: RequestSpec
    }

    var tabs: [Tab]
    var selectedID: UUID?
}

/// Stores history and open tabs as JSON in ~/Library/Application Support/Courier.
nonisolated struct Persistence {
    let directory: URL
    private let logger = Logger(subsystem: "dev.courier.app", category: "persistence")

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "Courier", directoryHint: .isDirectory)
    }

    func loadHistory() -> [HistoryEntry] { load("history.json") ?? [] }
    func saveHistory(_ history: [HistoryEntry]) { save(history, to: "history.json") }

    func loadTabs() -> TabsSnapshot? { load("tabs.json") }
    func saveTabs(_ snapshot: TabsSnapshot) { save(snapshot, to: "tabs.json") }

    private func load<T: Decodable>(_ name: String) -> T? {
        let url = directory.appending(path: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("Failed to decode \(name): \(error.localizedDescription)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(value).write(to: directory.appending(path: name), options: .atomic)
        } catch {
            logger.error("Failed to save \(name): \(error.localizedDescription)")
        }
    }
}
