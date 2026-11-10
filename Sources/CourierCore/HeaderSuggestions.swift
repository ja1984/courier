import Foundation

/// Autocomplete for request headers: common header names and, per name, typical values.
/// Headers you've used before (in history and collections) are suggested too, but values of
/// secret-looking headers never are, so tokens don't pop up in a dropdown.
public struct HeaderSuggestions: Sendable {
    public static let maxResults = 8

    /// Header names, built-in first, then ones learned from your requests.
    public private(set) var names: [String]
    /// Values per lowercased header name.
    private var valuesByName: [String: [String]]

    public init(learnedFrom specs: [RequestSpec] = []) {
        var names = Self.commonNames
        var seenNames = Set(names.map { $0.lowercased() })
        var values = Self.commonValues
        var seenValues = Set(values.flatMap { name, list in list.map { "\(name)\n\($0.lowercased())" } })

        for spec in specs {
            for header in spec.headers {
                let name = header.key.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let lower = name.lowercased()
                if seenNames.insert(lower).inserted { names.append(name) }

                let value = header.value.trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty, !SensitiveHeaders.isSensitive(name) else { continue }
                if seenValues.insert("\(lower)\n\(value.lowercased())").inserted {
                    values[lower, default: []].append(value)
                }
            }
        }
        self.names = names
        self.valuesByName = values
    }

    /// Header names matching what's typed. Nothing for an empty field or an exact match,
    /// and names already used in other rows are left out.
    public func names(matching input: String, excluding used: Set<String> = []) -> [String] {
        let query = input.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let usedLower = Set(used.map { $0.lowercased() })
        let candidates = names.filter { !usedLower.contains($0.lowercased()) }
        return Self.rank(candidates, query: query)
    }

    /// Values for a header name matching what's typed. With an empty field, all of them.
    public func values(for name: String, matching input: String) -> [String] {
        let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard let values = valuesByName[lower], !values.isEmpty else { return [] }
        let query = input.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return Array(values.prefix(Self.maxResults)) }
        return Self.rank(values, query: query)
    }

    /// Prefix matches first, then matches inside the text (so "type" finds Content-Type).
    private static func rank(_ candidates: [String], query: String) -> [String] {
        let q = query.lowercased()
        if candidates.contains(where: { $0.lowercased() == q }) { return [] }
        var prefix: [String] = []
        var inside: [String] = []
        for candidate in candidates {
            let lower = candidate.lowercased()
            if lower.hasPrefix(q) {
                prefix.append(candidate)
            } else if lower.contains(q) {
                inside.append(candidate)
            }
        }
        return Array((prefix + inside).prefix(maxResults))
    }

    public static let commonNames = [
        "Accept",
        "Accept-Encoding",
        "Accept-Language",
        "Authorization",
        "Cache-Control",
        "Connection",
        "Content-Encoding",
        "Content-Language",
        "Content-Type",
        "Cookie",
        "DNT",
        "Forwarded",
        "From",
        "Host",
        "If-Match",
        "If-Modified-Since",
        "If-None-Match",
        "If-Unmodified-Since",
        "Idempotency-Key",
        "Origin",
        "Pragma",
        "Prefer",
        "Range",
        "Referer",
        "User-Agent",
        "X-API-Key",
        "X-Correlation-ID",
        "X-CSRF-Token",
        "X-Forwarded-For",
        "X-Forwarded-Host",
        "X-Forwarded-Proto",
        "X-Request-ID",
        "X-Requested-With",
    ]

    private static let mediaTypes = [
        "application/json",
        "application/x-www-form-urlencoded",
        "multipart/form-data",
        "text/plain",
        "text/html",
        "application/xml",
        "text/xml",
        "application/octet-stream",
        "application/graphql",
        "application/ld+json",
        "application/problem+json",
    ]

    /// Keyed by lowercased header name.
    public static let commonValues: [String: [String]] = [
        "accept": ["application/json", "*/*", "text/html", "text/plain", "application/xml", "text/event-stream"],
        "accept-encoding": ["gzip, deflate, br", "gzip", "identity"],
        "accept-language": ["en-US,en;q=0.9", "en", "sv-SE,sv;q=0.9,en;q=0.8"],
        "authorization": ["Bearer ", "Basic "],
        "cache-control": ["no-cache", "no-store", "max-age=0", "must-revalidate"],
        "connection": ["keep-alive", "close"],
        "content-encoding": ["gzip", "br", "deflate"],
        "content-type": mediaTypes,
        "dnt": ["1"],
        "pragma": ["no-cache"],
        "prefer": ["return=representation", "return=minimal", "respond-async"],
        "range": ["bytes=0-1023"],
        "user-agent": ["Courier", "curl/8.7.1"],
        "x-forwarded-proto": ["https", "http"],
        "x-requested-with": ["XMLHttpRequest"],
    ]
}
