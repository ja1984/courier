import Foundation

/// Exports collections as Courier JSON, and imports Courier or Postman (v2.0/v2.1) collection files.
public enum CollectionTransfer {
    public static let formatID = "courier.collections"
    public static let formatVersion = 1

    public enum TransferError: Error, Equatable, LocalizedError {
        case unrecognizedFile
        case unsupportedVersion(Int)
        case empty

        public var errorDescription: String? {
            switch self {
            case .unrecognizedFile:
                "This isn't a Courier or Postman collection file."
            case .unsupportedVersion(let version):
                "This file was made by a newer version of Courier (format \(version)). Update Courier to import it."
            case .empty:
                "The file doesn't contain any requests."
            }
        }
    }

    public struct ImportResult: Sendable {
        public var collections: [RequestCollection]
        /// Things that didn't carry over exactly, worth telling the user.
        public var notes: [String]

        public var requestCount: Int { collections.reduce(0) { $0 + $1.requests.count } }
    }

    private struct CourierFile: Codable {
        var format: String
        var version: Int
        var exported: Date
        var collections: [RequestCollection]
    }

    // MARK: Export

    /// Courier's export file. Without `includeSecrets`, values of secret-looking headers and
    /// query parameters (see `SensitiveHeaders`) are written empty, keeping their names.
    public static func export(_ collections: [RequestCollection], includeSecrets: Bool, at date: Date = Date()) throws -> Data {
        let exported = includeSecrets ? collections : collections.map(withoutSecrets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(CourierFile(format: formatID, version: formatVersion, exported: date, collections: exported))
    }

    public static func withoutSecrets(_ collection: RequestCollection) -> RequestCollection {
        var copy = collection
        copy.requests = collection.requests.map { request in
            var request = request
            request.spec = withoutSecrets(request.spec)
            return request
        }
        return copy
    }

    public static func withoutSecrets(_ spec: RequestSpec) -> RequestSpec {
        var spec = spec
        spec.headers = spec.headers.map(blankIfSecret)
        if spec.params.contains(where: { SensitiveHeaders.isSensitive($0.key) && !$0.value.isEmpty }) {
            spec.setParams(spec.params.map(blankIfSecret))
        }
        spec.formFields = spec.formFields.map(blankIfSecret)
        // user:password@host
        if var components = URLComponents(string: spec.url), components.password != nil {
            components.password = nil
            components.user = nil
            spec.url = components.string ?? spec.url
        }
        return spec
    }

    private static func blankIfSecret(_ item: KeyValue) -> KeyValue {
        guard SensitiveHeaders.isSensitive(item.key) else { return item }
        var item = item
        item.value = ""
        return item
    }

    // MARK: Import

    /// Reads a Courier or Postman file. Everything gets fresh ids, so importing never replaces existing data.
    public static func importFile(_ data: Data) throws -> ImportResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TransferError.unrecognizedFile
        }
        if root["format"] as? String == formatID {
            let result = try importCourier(data, version: root["version"] as? Int ?? 0)
            // Empty collections are fine in a Courier backup; an empty file isn't.
            guard !result.collections.isEmpty else { throw TransferError.empty }
            return result
        }
        if root["info"] is [String: Any], root["item"] is [Any] {
            let result = PostmanImporter(root: root).run()
            guard result.requestCount > 0 else { throw TransferError.empty }
            return result
        }
        throw TransferError.unrecognizedFile
    }

    private static func importCourier(_ data: Data, version: Int) throws -> ImportResult {
        guard version <= formatVersion else { throw TransferError.unsupportedVersion(version) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(CourierFile.self, from: data)
        let collections = file.collections.map { collection in
            RequestCollection(
                name: collection.name,
                color: collection.color,
                requests: collection.requests.map { SavedRequest(name: $0.name, spec: $0.spec, updated: $0.updated) }
            )
        }
        return ImportResult(collections: collections, notes: [])
    }
}

// MARK: - Postman

/// Converts a Postman Collection (v2.0/v2.1) into one Courier collection.
/// Folders are flattened into request names ("Users / Get user"); auth becomes headers or params.
private struct PostmanImporter {
    let root: [String: Any]
    private var requests: [SavedRequest] = []
    private var notes: Set<String> = []
    private var usesVariables = false

    init(root: [String: Any]) {
        self.root = root
    }

    func run() -> CollectionTransfer.ImportResult {
        var importer = self
        let info = root["info"] as? [String: Any]
        let name = (info?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Imported from Postman"
        importer.walk(root["item"] as? [Any] ?? [], path: [], inheritedAuth: root["auth"] as? [String: Any])
        if importer.usesVariables {
            importer.notes.insert("Some requests use {{variables}}. Courier keeps them as text; replace them before sending.")
        }
        return CollectionTransfer.ImportResult(
            collections: [RequestCollection(name: name, requests: importer.requests)],
            notes: importer.notes.sorted()
        )
    }

    private mutating func walk(_ items: [Any], path: [String], inheritedAuth: [String: Any]?) {
        for case let item as [String: Any] in items {
            let name = item["name"] as? String ?? "Untitled"
            let auth = item["auth"] as? [String: Any] ?? inheritedAuth
            if let children = item["item"] as? [Any] {
                walk(children, path: path + [name], inheritedAuth: auth)
            } else if let request = item["request"] {
                let spec = makeSpec(request, auth: auth)
                requests.append(SavedRequest(name: (path + [name]).joined(separator: " / "), spec: spec))
            }
        }
    }

    private mutating func makeSpec(_ value: Any, auth inherited: [String: Any]?) -> RequestSpec {
        var spec = RequestSpec()
        // v2.1 allows a bare URL string as the whole request.
        guard let request = value as? [String: Any] else {
            spec.setURL(value as? String ?? "")
            noteVariables(in: spec.url)
            return spec
        }
        spec.method = HTTPMethod(rawValue: request["method"] as? String ?? "GET")

        var disabledParams: [KeyValue] = []
        let url = request["url"]
        if let string = url as? String {
            spec.setURL(string)
        } else if let object = url as? [String: Any] {
            spec.setURL(object["raw"] as? String ?? Self.buildURL(object))
            for case let query as [String: Any] in object["query"] as? [Any] ?? [] where query["disabled"] as? Bool == true {
                disabledParams.append(KeyValue(query["key"] as? String ?? "", query["value"] as? String ?? "", isEnabled: false))
            }
        }
        if !disabledParams.isEmpty { spec.params += disabledParams }

        for case let header as [String: Any] in request["header"] as? [Any] ?? [] {
            spec.headers.append(KeyValue(
                header["key"] as? String ?? "",
                header["value"] as? String ?? "",
                isEnabled: header["disabled"] as? Bool != true
            ))
        }

        applyAuth(request["auth"] as? [String: Any] ?? inherited, to: &spec)
        applyBody(request["body"] as? [String: Any], to: &spec)

        noteVariables(in: spec.url)
        spec.headers.forEach { noteVariables(in: $0.value) }
        noteVariables(in: spec.bodyText)
        return spec
    }

    private mutating func applyAuth(_ auth: [String: Any]?, to spec: inout RequestSpec) {
        guard let auth, let type = auth["type"] as? String, type != "noauth" else { return }
        // v2.1: [{key, value}]; v2.0: {key: value}
        func field(_ key: String) -> String? {
            if let list = auth[type] as? [[String: Any]] {
                return list.first { $0["key"] as? String == key }?["value"].map { "\($0)" }
            }
            return (auth[type] as? [String: Any])?[key].map { "\($0)" }
        }
        let hasAuthorization = spec.headers.contains { $0.key.caseInsensitiveCompare("Authorization") == .orderedSame }
        switch type {
        case "bearer":
            if !hasAuthorization { spec.headers.append(KeyValue("Authorization", "Bearer \(field("token") ?? "")")) }
        case "basic":
            let credentials = Data("\(field("username") ?? ""):\(field("password") ?? "")".utf8).base64EncodedString()
            if !hasAuthorization { spec.headers.append(KeyValue("Authorization", "Basic \(credentials)")) }
        case "apikey":
            let key = field("key") ?? "X-API-Key"
            let value = field("value") ?? ""
            if field("in") == "query" {
                spec.setParams(spec.params + [KeyValue(key, value)])
            } else {
                spec.headers.append(KeyValue(key, value))
            }
        default:
            notes.insert("Postman “\(type)” auth isn't supported; add those headers yourself.")
        }
    }

    private mutating func applyBody(_ body: [String: Any]?, to spec: inout RequestSpec) {
        guard let body, let mode = body["mode"] as? String else { return }
        switch mode {
        case "raw":
            let text = body["raw"] as? String ?? ""
            guard !text.isEmpty else { return }
            let language = ((body["options"] as? [String: Any])?["raw"] as? [String: Any])?["language"] as? String
            spec.bodyKind = language == "json" || JSONFormatter.isValid(text) ? .json : .text
            spec.bodyText = text
        case "urlencoded", "formdata":
            var skippedFiles = false
            spec.formFields = (body[mode] as? [Any] ?? []).compactMap { entry in
                guard let entry = entry as? [String: Any] else { return nil }
                if entry["type"] as? String == "file" {
                    skippedFiles = true
                    return nil
                }
                return KeyValue(entry["key"] as? String ?? "", entry["value"] as? String ?? "", isEnabled: entry["disabled"] as? Bool != true)
            }
            if !spec.formFields.isEmpty { spec.bodyKind = .form }
            if skippedFiles { notes.insert("File fields in form-data bodies were skipped; Courier can't upload files yet.") }
            if mode == "formdata" { notes.insert("Form-data bodies are sent URL-encoded in Courier.") }
        case "graphql":
            let graphql = body["graphql"] as? [String: Any] ?? [:]
            var payload: [String: Any] = ["query": graphql["query"] as? String ?? ""]
            if let variables = graphql["variables"] as? String,
               let parsed = try? JSONSerialization.jsonObject(with: Data(variables.utf8)) {
                payload["variables"] = parsed
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                spec.bodyKind = .json
                spec.bodyText = String(decoding: data, as: UTF8.self)
            }
        default:
            notes.insert("Postman “\(mode)” bodies aren't supported and were left out.")
        }
    }

    private mutating func noteVariables(in text: String) {
        if text.contains("{{") && text.contains("}}") { usesVariables = true }
    }

    /// URL from Postman's structured form, for files without "raw".
    private static func buildURL(_ url: [String: Any]) -> String {
        func joined(_ value: Any?, _ separator: String) -> String {
            if let list = value as? [Any] { return list.map { "\($0)" }.joined(separator: separator) }
            return value as? String ?? ""
        }
        var result = ""
        if let scheme = url["protocol"] as? String { result += "\(scheme)://" }
        result += joined(url["host"], ".")
        if let port = url["port"] as? String { result += ":\(port)" }
        let path = joined(url["path"], "/")
        if !path.isEmpty { result += "/" + path }
        let query = (url["query"] as? [[String: Any]] ?? [])
            .filter { $0["disabled"] as? Bool != true }
            .map { "\($0["key"] as? String ?? "")=\($0["value"] as? String ?? "")" }
        if !query.isEmpty { result += "?" + query.joined(separator: "&") }
        return result
    }
}

extension CollectionLibrary {
    /// Adds imported collections, renaming any whose name is already taken ("API 2"). Returns their ids.
    @discardableResult
    public mutating func add(_ imported: [RequestCollection]) -> [UUID] {
        imported.map { collection in
            var collection = collection
            let taken = Set(collections.map(\.name))
            if taken.contains(collection.name) {
                var n = 2
                while taken.contains("\(collection.name) \(n)") { n += 1 }
                collection.name = "\(collection.name) \(n)"
            }
            collections.append(collection)
            return collection.id
        }
    }
}
