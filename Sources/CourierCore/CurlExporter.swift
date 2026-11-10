import Foundation

public enum CurlExporter {
    public static func command(for spec: RequestSpec) -> String {
        var first = "curl"
        // With a body curl defaults to POST, so a GET-with-body still needs an explicit -X.
        if spec.method != .get || spec.encodedBody != nil {
            first += " -X " + spec.method.rawValue
        }
        first += " " + shellQuote(spec.url.trimmed)

        var lines = [first]
        for header in spec.effectiveHeaders where header.name.caseInsensitiveCompare("Cookie") != .orderedSame {
            lines.append("-H " + shellQuote("\(header.name): \(header.value)"))
        }
        // The request's own cookies (not the cookie jar's, which may hold your sessions).
        let cookies = spec.requestCookies
        if !cookies.isEmpty {
            lines.append("-b " + shellQuote(CookiePair.header(cookies)))
        }
        if let body = spec.encodedBody {
            lines.append("--data-raw " + shellQuote(body))
        }
        return lines.joined(separator: " \\\n  ")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
