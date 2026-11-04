import CryptoKit
import Foundation

/// Stores Codable values as AES-256-GCM encrypted files (`<name>.sealed`).
///
/// - Never writes plaintext. Without a key, saving fails.
/// - Reads a legacy plaintext `<name>.json` once so it can be migrated, and deletes it
///   after the first successful encrypted save.
/// - A sealed file that can't be decrypted is moved aside instead of being overwritten,
///   so a temporarily missing key can't destroy data.
public struct SealedFileStore: Sendable {
    public enum StoreError: Error, Equatable {
        case noKey
        case unreadable(movedTo: URL)
        case invalidFormat
    }

    public let directory: URL
    private let key: SymmetricKey?

    /// "CRSV" + format version 1.
    private static let magic = Data("CRSV".utf8) + Data([1])

    public init(directory: URL, key: SymmetricKey?) {
        self.directory = directory
        self.key = key
    }

    public var canSave: Bool { key != nil }

    public func sealedURL(_ name: String) -> URL { directory.appending(path: "\(name).sealed") }
    public func legacyURL(_ name: String) -> URL { directory.appending(path: "\(name).json") }

    public func hasLegacyPlaintext(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: legacyURL(name).path)
    }

    public func load<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sealed = sealedURL(name)

        if FileManager.default.fileExists(atPath: sealed.path) {
            guard let key else { throw StoreError.noKey }
            do {
                let plaintext = try Self.open(try Data(contentsOf: sealed), key: key)
                return try decoder.decode(T.self, from: plaintext)
            } catch {
                let aside = sealed.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
                try? FileManager.default.moveItem(at: sealed, to: aside)
                throw StoreError.unreadable(movedTo: aside)
            }
        }

        let legacy = legacyURL(name)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return nil }
        return try decoder.decode(T.self, from: try Data(contentsOf: legacy))
    }

    public func save<T: Encodable>(_ value: T, name: String) throws {
        guard let key else { throw StoreError.noKey }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sealedData = try Self.seal(try encoder.encode(value), key: key)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = sealedURL(name)
        try sealedData.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        // The encrypted copy is safely on disk; drop the plaintext one.
        if hasLegacyPlaintext(name) {
            try FileManager.default.removeItem(at: legacyURL(name))
        }
    }

    // MARK: Format

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else { throw StoreError.invalidFormat }
        return magic + combined
    }

    static func open(_ data: Data, key: SymmetricKey) throws -> Data {
        guard data.starts(with: magic) else { throw StoreError.invalidFormat }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
        return try AES.GCM.open(box, using: key)
    }
}
