import Foundation

/// A request saved under a name in a collection. Saved requests are never trimmed like history.
public struct SavedRequest: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var spec: RequestSpec
    public var updated: Date

    public init(id: UUID = UUID(), name: String, spec: RequestSpec, updated: Date = Date()) {
        self.id = id
        self.name = name
        self.spec = spec
        self.updated = updated
    }
}

/// A label color for a collection, shown in the sidebar and on its tabs (like Finder tags).
public enum CollectionColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case red, orange, yellow, green, teal, blue, purple, pink, gray

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct RequestCollection: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// nil for no color. Missing in files from older versions.
    public var color: CollectionColor?
    public var requests: [SavedRequest]

    public init(id: UUID = UUID(), name: String, color: CollectionColor? = nil, requests: [SavedRequest] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.requests = requests
    }
}

/// All collections, with the edits the app makes to them. Pure value logic, so it's easy to test.
public struct CollectionLibrary: Hashable, Codable, Sendable {
    public var collections: [RequestCollection]

    public init(collections: [RequestCollection] = []) {
        self.collections = collections
    }

    public var isEmpty: Bool { collections.isEmpty }
    public var requestCount: Int { collections.reduce(0) { $0 + $1.requests.count } }

    public func collection(_ id: UUID) -> RequestCollection? {
        collections.first { $0.id == id }
    }

    /// The saved request and the collection it's in.
    public func request(_ id: UUID) -> (collection: RequestCollection, request: SavedRequest)? {
        for collection in collections {
            if let request = collection.requests.first(where: { $0.id == id }) {
                return (collection, request)
            }
        }
        return nil
    }

    // MARK: Collections

    /// Adds a collection and returns its id. Blank names become "Untitled Collection".
    @discardableResult
    public mutating func addCollection(named name: String) -> UUID {
        let collection = RequestCollection(name: Self.cleanName(name, fallback: "Untitled Collection"))
        collections.append(collection)
        return collection.id
    }

    public mutating func renameCollection(_ id: UUID, to name: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = Self.cleanName(name, fallback: collections[index].name)
    }

    public mutating func setColor(_ color: CollectionColor?, for id: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].color = color
    }

    public mutating func deleteCollection(_ id: UUID) {
        collections.removeAll { $0.id == id }
    }

    // MARK: Requests

    /// Saves a new request into a collection and returns its id, or nil if the collection doesn't exist.
    @discardableResult
    public mutating func saveRequest(_ spec: RequestSpec, named name: String, in collectionID: UUID, at date: Date = Date()) -> UUID? {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return nil }
        let request = SavedRequest(name: Self.cleanName(name, fallback: Self.suggestedName(for: spec)), spec: spec, updated: date)
        collections[index].requests.append(request)
        return request.id
    }

    /// Replaces a saved request's contents. Returns false if it no longer exists.
    @discardableResult
    public mutating func updateRequest(_ id: UUID, spec: RequestSpec, at date: Date = Date()) -> Bool {
        modifyRequest(id) {
            $0.spec = spec
            $0.updated = date
        }
    }

    public mutating func renameRequest(_ id: UUID, to name: String) {
        modifyRequest(id) { $0.name = Self.cleanName(name, fallback: $0.name) }
    }

    /// Copies a request right below the original, named "<name> copy". Returns the copy's id.
    @discardableResult
    public mutating func duplicateRequest(_ id: UUID) -> UUID? {
        for c in collections.indices {
            guard let r = collections[c].requests.firstIndex(where: { $0.id == id }) else { continue }
            let original = collections[c].requests[r]
            let copy = SavedRequest(name: "\(original.name) copy", spec: original.spec, updated: Date())
            collections[c].requests.insert(copy, at: r + 1)
            return copy.id
        }
        return nil
    }

    public mutating func deleteRequest(_ id: UUID) {
        for c in collections.indices {
            collections[c].requests.removeAll { $0.id == id }
        }
    }

    @discardableResult
    private mutating func modifyRequest(_ id: UUID, _ change: (inout SavedRequest) -> Void) -> Bool {
        for c in collections.indices {
            if let r = collections[c].requests.firstIndex(where: { $0.id == id }) {
                change(&collections[c].requests[r])
                return true
            }
        }
        return false
    }

    // MARK: Search & naming

    /// Collections with only the requests matching the query (name, method or URL).
    /// A collection whose own name matches keeps all its requests.
    public func filtered(by query: String) -> [RequestCollection] {
        let query = query.trimmed
        guard !query.isEmpty else { return collections }
        return collections.compactMap { collection in
            if collection.name.localizedCaseInsensitiveContains(query) { return collection }
            var copy = collection
            copy.requests = collection.requests.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.spec.url.localizedCaseInsensitiveContains(query)
                    || $0.spec.method.rawValue.localizedCaseInsensitiveContains(query)
            }
            return copy.requests.isEmpty ? nil : copy
        }
    }

    /// A readable default name: the last meaningful path segments, else the host.
    public static func suggestedName(for spec: RequestSpec) -> String {
        let summary = spec.urlSummary
        let segments = summary.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if !segments.isEmpty {
            return segments.suffix(2).joined(separator: "/")
        }
        return summary.host ?? "New Request"
    }

    /// A default collection name for a request: its host, without "www.".
    public static func suggestedCollectionName(for spec: RequestSpec) -> String {
        guard var host = spec.hostLabel else { return "My Requests" }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private static func cleanName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmed
        return trimmed.isEmpty ? fallback : trimmed
    }
}
