import Foundation

public struct HTTPMethod: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public var id: String { rawValue }

    public static let get = HTTPMethod(rawValue: "GET")
    public static let post = HTTPMethod(rawValue: "POST")
    public static let put = HTTPMethod(rawValue: "PUT")
    public static let patch = HTTPMethod(rawValue: "PATCH")
    public static let delete = HTTPMethod(rawValue: "DELETE")
    public static let head = HTTPMethod(rawValue: "HEAD")
    public static let options = HTTPMethod(rawValue: "OPTIONS")

    public static let common: [HTTPMethod] = [.get, .post, .put, .patch, .delete, .head, .options]
}

public struct KeyValue: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var key: String
    public var value: String

    public init(_ key: String = "", _ value: String = "", isEnabled: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.isEnabled = isEnabled
        self.key = key
        self.value = value
    }
}

public enum BodyKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, json, text, form
    public var id: String { rawValue }
}

public struct RequestSpec: Hashable, Codable, Sendable {
    public var method: HTTPMethod
    /// Full URL including the query string built from enabled params.
    public var url: String
    /// All query params, including disabled ones (which are not in `url`).
    public var params: [KeyValue]
    public var headers: [KeyValue]
    public var bodyKind: BodyKind
    public var bodyText: String
    public var formFields: [KeyValue]
    /// Cookies set on this request (the Cookies tab), sent in the Cookie header.
    public var cookies: [KeyValue]

    public init(
        method: HTTPMethod = .get,
        url: String = "",
        params: [KeyValue] = [],
        headers: [KeyValue] = [],
        bodyKind: BodyKind = .none,
        bodyText: String = "",
        formFields: [KeyValue] = [],
        cookies: [KeyValue] = []
    ) {
        self.method = method
        self.url = url
        self.params = params
        self.headers = headers
        self.bodyKind = bodyKind
        self.bodyText = bodyText
        self.formFields = formFields
        self.cookies = cookies
    }

    /// Update the URL and re-derive params from its query, keeping disabled params.
    public mutating func setURL(_ newURL: String) {
        url = newURL
        params = URLQuery.params(from: newURL) + params.filter { !$0.isEnabled }
    }

    /// Update params and rebuild the URL's query string from the enabled ones.
    public mutating func setParams(_ newParams: [KeyValue]) {
        params = newParams
        url = URLQuery.replacingQuery(in: url, with: newParams)
    }

    /// The request's own cookies: those in Cookie headers, then the Cookies tab.
    /// A later cookie replaces an earlier one with the same name.
    public var requestCookies: [CookiePair] {
        let fromHeaders = headers
            .filter { $0.isEnabled && $0.key.trimmed.caseInsensitiveCompare("Cookie") == .orderedSame }
            .flatMap { CookiePair.parse($0.value) }
        let fromTab = cookies
            .filter { $0.isEnabled && !$0.key.trimmed.isEmpty }
            .map { CookiePair(name: $0.key.trimmed, value: $0.value) }
        return CookiePair.merged(fromHeaders + fromTab)
    }

    public var enabledHeaders: [KeyValue] {
        headers.filter { $0.isEnabled && !$0.key.trimmed.isEmpty }
    }

    /// The body that will be sent, or nil when there is none.
    public var encodedBody: String? {
        switch bodyKind {
        case .none:
            return nil
        case .json, .text:
            return bodyText.isEmpty ? nil : bodyText
        case .form:
            let encoded = URLQuery.encodeForm(formFields)
            return encoded.isEmpty ? nil : encoded
        }
    }

    public var defaultContentType: String? {
        switch bodyKind {
        case .none: nil
        case .json: "application/json"
        case .text: "text/plain; charset=utf-8"
        case .form: "application/x-www-form-urlencoded"
        }
    }

    /// Headers that will actually be sent, including an implicit Content-Type for the body.
    public var effectiveHeaders: [(name: String, value: String)] {
        var result = enabledHeaders.map { (name: $0.key.trimmed, value: $0.value) }
        let hasContentType = result.contains { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
        if encodedBody != nil, !hasContentType, let contentType = defaultContentType {
            result.append((name: "Content-Type", value: contentType))
        }
        return result
    }

    /// Same request content, ignoring the internal ids of params, headers and form fields
    /// (re-deriving params from the same URL creates new ids but changes nothing).
    public func hasSameContent(as other: RequestSpec) -> Bool {
        func rows(_ items: [KeyValue]) -> [String] { items.map { "\($0.isEnabled)\u{1}\($0.key)\u{1}\($0.value)" } }
        return method == other.method && url == other.url && bodyKind == other.bodyKind && bodyText == other.bodyText
            && rows(params) == rows(other.params) && rows(headers) == rows(other.headers)
            && rows(formFields) == rows(other.formFields) && rows(cookies) == rows(other.cookies)
    }

    /// Host and path for compact display (tab titles, history rows).
    public var urlSummary: (host: String?, path: String) {
        var raw = url.trimmed
        guard !raw.isEmpty else { return (nil, "") }
        if !raw.contains("://") { raw = "http://" + raw }
        guard let parsed = URL(string: raw) else { return (nil, url) }
        return (parsed.host(), parsed.path())
    }
}

public struct HistoryEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var date: Date
    public var spec: RequestSpec
    public var statusCode: Int?
    public var durationMs: Int?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        spec: RequestSpec,
        statusCode: Int? = nil,
        durationMs: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.date = date
        self.spec = spec
        self.statusCode = statusCode
        self.durationMs = durationMs
        self.errorMessage = errorMessage
    }
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension RequestSpec {
    /// Decodes files from older versions too, which have no `cookies`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(HTTPMethod.self, forKey: .method)
        url = try container.decode(String.self, forKey: .url)
        params = try container.decode([KeyValue].self, forKey: .params)
        headers = try container.decode([KeyValue].self, forKey: .headers)
        bodyKind = try container.decode(BodyKind.self, forKey: .bodyKind)
        bodyText = try container.decode(String.self, forKey: .bodyText)
        formFields = try container.decode([KeyValue].self, forKey: .formFields)
        cookies = try container.decodeIfPresent([KeyValue].self, forKey: .cookies) ?? []
    }
}
