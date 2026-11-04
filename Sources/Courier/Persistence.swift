import CourierCore
import CryptoKit
import Foundation
import os
import Security

nonisolated struct TabsSnapshot: Codable {
    struct Tab: Codable {
        var id: UUID
        var spec: RequestSpec
    }

    var tabs: [Tab]
    var selectedID: UUID?
}

/// Stores history and open tabs encrypted (AES-256-GCM) in ~/Library/Application Support/Courier.
/// The key lives in the login Keychain. Nothing is ever written in plaintext.
nonisolated struct Persistence {
    private let store: SealedFileStore
    private let logger = Logger(subsystem: "dev.courier.app", category: "persistence")
    /// Why tabs and history can't be saved this session, if they can't.
    let unavailableReason: String?

    /// `COURIER_DATA_DIR` points the app at another folder, e.g. for demos and screenshots,
    /// without touching your real tabs and history.
    init(directory: URL? = nil) {
        let resolved: URL
        if let directory {
            resolved = directory
        } else if let override = ProcessInfo.processInfo.environment["COURIER_DATA_DIR"], !override.isEmpty {
            resolved = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            resolved = URL.applicationSupportDirectory.appending(path: "Courier", directoryHint: .isDirectory)
        }

        do {
            store = SealedFileStore(directory: resolved, key: try StorageKey.loadOrCreate())
            unavailableReason = nil
        } catch {
            store = SealedFileStore(directory: resolved, key: nil)
            unavailableReason = error.localizedDescription
            logger.error("No storage key: \(error.localizedDescription)")
        }
    }

    /// Plaintext files from older versions that should be re-saved encrypted.
    var hasLegacyPlaintext: Bool {
        store.hasLegacyPlaintext("history") || store.hasLegacyPlaintext("tabs")
    }

    func loadHistory() -> [HistoryEntry] { load([HistoryEntry].self, "history") ?? [] }
    func saveHistory(_ history: [HistoryEntry]) { save(history, "history") }

    func loadTabs() -> TabsSnapshot? { load(TabsSnapshot.self, "tabs") }
    func saveTabs(_ snapshot: TabsSnapshot) { save(snapshot, "tabs") }

    private func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        do {
            return try store.load(type, name: name)
        } catch {
            logger.error("Failed to load \(name): \(String(describing: error))")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard store.canSave else { return }
        do {
            try store.save(value, name: name)
        } catch {
            logger.error("Failed to save \(name): \(String(describing: error))")
        }
    }
}

/// The 256-bit storage key, kept as a generic password in the login Keychain.
/// It isn't synced via iCloud, but it travels with the login keychain in account
/// backups and migrations, like any other saved password.
nonisolated enum StorageKey {
    private static let service = "dev.courier.app.storage"
    private static let account = "storage-encryption-key"

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Courier couldn't access its encryption key in the Keychain (\(message))."
        }
    }

    static func loadOrCreate() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        // Only create a key when there definitely isn't one. Any other failure (denied,
        // locked keychain) must not replace the existing key, or saved data becomes unreadable.
        guard status == errSecItemNotFound else {
            throw KeychainError(status: status == errSecSuccess ? errSecDecode : status)
        }

        let key = SymmetricKey(size: .bits256)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Courier storage key",
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
        ]
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        return key
    }
}
