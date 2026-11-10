import Foundation

/// A name/value pair as sent in a Cookie header.
public struct CookiePair: Hashable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    /// Parses a Cookie header value: "a=1; b=2". Pieces without a name are skipped.
    public static func parse(_ header: String) -> [CookiePair] {
        header.split(separator: ";").compactMap { piece in
            let piece = piece.trimmingCharacters(in: .whitespaces)
            guard let equals = piece.firstIndex(of: "=") else { return nil }
            let name = piece[..<equals].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return CookiePair(name: name, value: piece[piece.index(after: equals)...].trimmingCharacters(in: .whitespaces))
        }
    }

    /// Formats pairs as a Cookie header value.
    public static func header(_ pairs: [CookiePair]) -> String {
        pairs.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// Later pairs replace earlier ones with the same name (keeping the earlier position).
    public static func merged(_ pairs: [CookiePair]) -> [CookiePair] {
        var result: [CookiePair] = []
        var index: [String: Int] = [:]
        for pair in pairs {
            if let existing = index[pair.name] {
                result[existing] = pair
            } else {
                index[pair.name] = result.count
                result.append(pair)
            }
        }
        return result
    }
}

/// A cookie a server set, as kept in the cookie jar.
public struct StoredCookie: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var value: String
    /// Lowercased, without a leading dot.
    public var domain: String
    /// Set without a Domain attribute: only sent to exactly this host, not its subdomains.
    public var hostOnly: Bool
    public var path: String
    /// Nil for session cookies (no Expires/Max-Age). Courier keeps those until you clear them.
    public var expires: Date?
    public var secure: Bool
    public var httpOnly: Bool
    public var sameSite: String?

    /// A server replaces a cookie by setting one with the same name, domain and path.
    public var id: String { "\(hostOnly ? "" : ".")\(domain)\u{1}\(path)\u{1}\(name)" }

    public init(
        name: String,
        value: String,
        domain: String,
        hostOnly: Bool = true,
        path: String = "/",
        expires: Date? = nil,
        secure: Bool = false,
        httpOnly: Bool = false,
        sameSite: String? = nil
    ) {
        self.name = name
        self.value = value
        let lower = domain.lowercased()
        self.domain = lower.hasPrefix(".") ? String(lower.dropFirst()) : lower
        self.hostOnly = hostOnly
        self.path = path.isEmpty ? "/" : path
        self.expires = expires
        self.secure = secure
        self.httpOnly = httpOnly
        self.sameSite = sameSite
    }

    init(_ cookie: HTTPCookie) {
        self.init(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            // Foundation marks cookies set with a Domain attribute by a leading dot.
            hostOnly: !cookie.domain.hasPrefix("."),
            path: cookie.path,
            expires: cookie.expiresDate,
            secure: cookie.isSecure,
            httpOnly: cookie.isHTTPOnly,
            sameSite: cookie.sameSitePolicy?.rawValue
        )
    }

    public func isExpired(at now: Date) -> Bool {
        expires.map { $0 <= now } ?? false
    }

    /// Whether a browser would send this cookie to `url` (RFC 6265 domain and path matching).
    public func matches(_ url: URL, at now: Date = Date()) -> Bool {
        guard !isExpired(at: now), let host = url.host()?.lowercased() else { return false }
        let domainMatches = host == domain || (!hostOnly && host.hasSuffix("." + domain))
        guard domainMatches else { return false }
        // Secure cookies need HTTPS, except on localhost (as in browsers).
        if secure, url.scheme?.lowercased() != "https", !Self.isLocal(host) { return false }
        return Self.pathMatches(requestPath: url.path(), cookiePath: path)
    }

    static func pathMatches(requestPath: String, cookiePath: String) -> Bool {
        let requestPath = requestPath.isEmpty ? "/" : requestPath
        if requestPath == cookiePath { return true }
        guard requestPath.hasPrefix(cookiePath) else { return false }
        return cookiePath.hasSuffix("/") || requestPath.dropFirst(cookiePath.count).hasPrefix("/")
    }

    private static func isLocal(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    /// Cookies from a response's Set-Cookie headers. Invalid ones (e.g. for another domain) are dropped.
    public static func fromResponse(_ response: HTTPURLResponse) -> [StoredCookie] {
        guard let url = response.url else { return [] }
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            if let key = field.key as? String, let value = field.value as? String { result[key] = value }
        }
        return fromHeaders(fields, for: url)
    }

    public static func fromHeaders(_ fields: [String: String], for url: URL) -> [StoredCookie] {
        HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).map(StoredCookie.init)
    }
}

/// Cookies remembered from responses, sent again to matching URLs.
public struct CookieJar: Codable, Hashable, Sendable {
    public private(set) var cookies: [StoredCookie]

    public init(cookies: [StoredCookie] = []) {
        self.cookies = cookies
    }

    public var isEmpty: Bool { cookies.isEmpty }

    /// Adds or replaces cookies. An expired one (Max-Age=0 or a past Expires) deletes its match,
    /// which is how servers log you out.
    public mutating func store(_ received: [StoredCookie], at now: Date = Date()) {
        for cookie in received {
            cookies.removeAll { $0.id == cookie.id }
            if !cookie.isExpired(at: now) { cookies.append(cookie) }
        }
        removeExpired(at: now)
    }

    /// Cookies to send to `url`, longest path first (the order browsers use).
    public func cookies(for url: URL, at now: Date = Date()) -> [StoredCookie] {
        cookies.enumerated()
            .filter { $0.element.matches(url, at: now) }
            .sorted { $0.element.path.count != $1.element.path.count ? $0.element.path.count > $1.element.path.count : $0.offset < $1.offset }
            .map(\.element)
    }

    public mutating func setValue(_ value: String, for id: StoredCookie.ID) {
        guard let index = cookies.firstIndex(where: { $0.id == id }) else { return }
        cookies[index].value = value
    }

    public mutating func remove(_ id: StoredCookie.ID) {
        cookies.removeAll { $0.id == id }
    }

    public mutating func removeAll(domain: String) {
        let domain = domain.lowercased()
        cookies.removeAll { $0.domain == domain }
    }

    public mutating func removeAll() {
        cookies.removeAll()
    }

    public mutating func removeExpired(at now: Date = Date()) {
        cookies.removeAll { $0.isExpired(at: now) }
    }

    /// The Cookie header for a request: jar cookies for its URL, overridden by the request's own.
    public static func cookieHeader(jar: [StoredCookie], request: [CookiePair]) -> String? {
        let pairs = CookiePair.merged(jar.map { CookiePair(name: $0.name, value: $0.value) } + request)
        return pairs.isEmpty ? nil : CookiePair.header(pairs)
    }
}
