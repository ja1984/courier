import CryptoKit
import Foundation
import Testing
@testable import CourierCore

@Suite struct SealedFileStoreTests {
    private struct Sample: Codable, Equatable {
        var secret: String
        var date: Date
    }

    private let sample = Sample(secret: "Cookie: session=abc123", date: Date(timeIntervalSince1970: 1_800_000_000))

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "courier-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripsAndNeverWritesPlaintext() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SealedFileStore(directory: dir, key: SymmetricKey(size: .bits256))

        try store.save(sample, name: "history")
        #expect(try store.load(Sample.self, name: "history") == sample)

        let raw = try Data(contentsOf: store.sealedURL("history"))
        #expect(raw.range(of: Data("session=abc123".utf8)) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.legacyURL("history").path))
        let permissions = try FileManager.default.attributesOfItem(atPath: store.sealedURL("history").path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func migratesLegacyPlaintextAndDeletesIt() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sample).write(to: dir.appending(path: "tabs.json"))

        let store = SealedFileStore(directory: dir, key: SymmetricKey(size: .bits256))
        #expect(store.hasLegacyPlaintext("tabs"))
        let loaded = try #require(try store.load(Sample.self, name: "tabs"))
        #expect(loaded == sample)

        try store.save(loaded, name: "tabs")
        #expect(!store.hasLegacyPlaintext("tabs"))
        #expect(try store.load(Sample.self, name: "tabs") == sample)
    }

    @Test func corruptLegacyFileIsKeptNotDeletedByMigration() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("{ not json".utf8).write(to: dir.appending(path: "history.json"))
        let store = SealedFileStore(directory: dir, key: SymmetricKey(size: .bits256))

        #expect(throws: (any Error).self) { try store.load([Sample].self, name: "history") }
        // What the app does next: save what it has (nothing). The corrupt original must survive.
        try store.save([Sample](), name: "history")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("history.json.unreadable-") })
    }

    @Test func refusesToSaveWithoutKey() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SealedFileStore(directory: dir, key: nil)
        #expect(throws: SealedFileStore.StoreError.noKey) { try store.save(sample, name: "history") }
        #expect(!FileManager.default.fileExists(atPath: store.legacyURL("history").path))
    }

    @Test func wrongKeyMovesFileAsideInsteadOfOverwriting() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try SealedFileStore(directory: dir, key: SymmetricKey(size: .bits256)).save(sample, name: "history")

        let other = SealedFileStore(directory: dir, key: SymmetricKey(size: .bits256))
        #expect(throws: (any Error).self) { try other.load(Sample.self, name: "history") }
        #expect(!FileManager.default.fileExists(atPath: other.sealedURL("history").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(leftovers.contains { $0.hasPrefix("history.sealed.unreadable-") })
    }

    @Test func tamperedDataFailsToOpen() throws {
        let key = SymmetricKey(size: .bits256)
        var sealed = try SealedFileStore.seal(Data("hello".utf8), key: key)
        sealed[sealed.count - 1] ^= 0xFF
        #expect(throws: (any Error).self) { try SealedFileStore.open(sealed, key: key) }
        #expect(throws: SealedFileStore.StoreError.invalidFormat) { try SealedFileStore.open(Data("nope".utf8), key: key) }
    }

    @Test func missingKeyWithSealedFileThrowsWithoutTouchingIt() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try SealedFileStore(directory: dir, key: SymmetricKey(size: .bits256)).save(sample, name: "history")
        let locked = SealedFileStore(directory: dir, key: nil)
        #expect(throws: SealedFileStore.StoreError.noKey) { try locked.load(Sample.self, name: "history") }
        #expect(FileManager.default.fileExists(atPath: locked.sealedURL("history").path))
    }
}
