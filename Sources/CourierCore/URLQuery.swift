import Foundation

public enum URLQuery {
    private static let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))

    public static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    public static func decode(_ value: some StringProtocol) -> String {
        let spaced = value.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    static func split(_ url: String) -> (base: String, query: String?, fragment: String?) {
        var rest = Substring(url)
        var fragment: String?
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = rest[..<hash]
        }
        guard let question = rest.firstIndex(of: "?") else {
            return (String(rest), nil, fragment)
        }
        return (String(rest[..<question]), String(rest[rest.index(after: question)...]), fragment)
    }

    public static func params(from url: String) -> [KeyValue] {
        guard let query = split(url).query, !query.isEmpty else { return [] }
        return query.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return KeyValue(decode(parts[0]), parts.count > 1 ? decode(parts[1]) : "")
        }
    }

    public static func replacingQuery(in url: String, with params: [KeyValue]) -> String {
        let parts = split(url)
        let query = encodePairs(params)
        var result = parts.base
        if !query.isEmpty { result += "?" + query }
        if let fragment = parts.fragment { result += "#" + fragment }
        return result
    }

    public static func encodeForm(_ fields: [KeyValue]) -> String {
        fields
            .filter { $0.isEnabled && !$0.key.isEmpty }
            .map { encode($0.key) + "=" + encode($0.value) }
            .joined(separator: "&")
    }

    /// Parses `a=1&b=2` style bodies. Returns nil if the text doesn't look form-encoded.
    public static func formFields(fromEncoded text: String) -> [KeyValue]? {
        guard !text.isEmpty, !text.contains(where: \.isNewline) else { return nil }
        var fields: [KeyValue] = []
        for pair in text.split(separator: "&", omittingEmptySubsequences: true) {
            guard let eq = pair.firstIndex(of: "="), eq != pair.startIndex else { return nil }
            fields.append(KeyValue(decode(pair[..<eq]), decode(pair[pair.index(after: eq)...])))
        }
        return fields.isEmpty ? nil : fields
    }

    private static func encodePairs(_ params: [KeyValue]) -> String {
        params
            .filter { $0.isEnabled && !$0.key.isEmpty }
            .map { $0.value.isEmpty ? encode($0.key) : encode($0.key) + "=" + encode($0.value) }
            .joined(separator: "&")
    }
}
