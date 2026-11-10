import Foundation

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [KeyValue]
    public let body: Data
    public let duration: Duration
    public let finalURL: URL?
    /// Body decoded as UTF-8, or nil for binary content.
    public let text: String?
    /// Format detected from Content-Type, falling back to the body.
    public let format: ResponseFormat
    /// Re-indented body for JSON/XML/HTML, or nil if it couldn't be parsed.
    public let prettyText: String?

    public init(
        statusCode: Int,
        headers: [KeyValue],
        body: Data,
        duration: Duration,
        finalURL: URL?,
        metrics: ResponseMetrics? = nil,
        receivedCookies: [StoredCookie] = []
    ) {
        let clock = ContinuousClock()
        let processingStart = clock.now
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.duration = duration
        self.finalURL = finalURL
        self.receivedCookies = receivedCookies
        let text = String(data: body, encoding: .utf8)
        self.text = text
        let contentType = headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
        let format = ResponseFormat.detect(contentType: contentType, text: text)
        self.format = format
        let prettyText = text.flatMap { format.prettyPrinted($0) }
        self.prettyText = prettyText
        jsonTree = format == .json && prettyText != nil ? text.flatMap { JSONTree($0) } : nil
        self.metrics = metrics?.appendingProcessing(clock.now - processingStart)
    }

    /// Distinguishes responses so per-response view state (like collapsed nodes) resets.
    public let id = UUID()
    /// Collapsible tree for JSON bodies.
    public let jsonTree: JSONTree?
    /// Cookies set by the response, including by redirects on the way, in order.
    public let receivedCookies: [StoredCookie]
    /// Timing, size and connection details, when the system provided them.
    public let metrics: ResponseMetrics?

    /// Bytes on the wire (headers + body), falling back to the body size.
    public var transferSize: Int64 {
        guard let metrics, metrics.responseBytes > 0 else { return Int64(body.count) }
        return metrics.responseBytes
    }

    public var contentType: String? {
        headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
    }

    public var durationMs: Int { Int((duration / .milliseconds(1)).rounded()) }

    public var statusText: String {
        HTTPStatus.reasonPhrase(for: statusCode)
    }
}

public enum RequestBuildError: Error, Equatable, LocalizedError {
    case emptyURL
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case .emptyURL: "Enter a URL to send the request."
        case .invalidURL(let url): "“\(url)” isn't a valid URL."
        }
    }
}

public enum HTTPClient {
    /// Builds the request. Cookies are sent as one Cookie header: those from the jar that match
    /// the URL, overridden by the request's own (Cookie headers and the Cookies tab).
    public static func makeURLRequest(from spec: RequestSpec, jar: CookieJar? = nil, at now: Date = Date()) throws -> URLRequest {
        var raw = spec.url.trimmed
        guard !raw.isEmpty else { throw RequestBuildError.emptyURL }
        if !raw.contains("://") { raw = "http://" + raw }
        guard let url = URL(string: raw), url.host() != nil else { throw RequestBuildError.invalidURL(spec.url) }

        var request = URLRequest(url: url)
        request.httpMethod = spec.method.rawValue
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 60
        for header in spec.effectiveHeaders where header.name.caseInsensitiveCompare("Cookie") != .orderedSame {
            request.addValue(header.value, forHTTPHeaderField: header.name)
        }
        // Courier handles cookies itself, so the system neither adds nor stores any.
        request.httpShouldHandleCookies = false
        let jarCookies = jar?.cookies(for: url, at: now) ?? []
        if let cookie = CookieJar.cookieHeader(jar: jarCookies, request: spec.requestCookies) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let body = spec.encodedBody {
            request.httpBody = Data(body.utf8)
        }
        return request
    }

    /// Sends on a fresh ephemeral session so every request gets its own connection:
    /// timings always include DNS/TCP/TLS, the certificate is always seen, and no
    /// cookies or cache leak between requests.
    /// With a `jar`, matching cookies are sent and cookies set along redirects are applied to the
    /// next hop; the caller decides whether to keep `receivedCookies`.
    public static func send(_ spec: RequestSpec, jar: CookieJar? = nil) async throws -> HTTPResponse {
        let request = try makeURLRequest(from: spec, jar: jar)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let collector = MetricsCollector(
            cookies: RedirectCookies(jar: jar, requestCookies: spec.requestCookies, originalHost: request.url?.host())
        )
        let session = URLSession(configuration: configuration, delegate: collector, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let clock = ContinuousClock()
        let start = clock.now
        let (data, response) = try await session.data(for: request)
        let duration = clock.now - start
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let headers = http.allHeaderFields
            .map { KeyValue("\($0.key)", "\($0.value)") }
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
        return HTTPResponse(
            statusCode: http.statusCode,
            headers: headers,
            body: data,
            duration: duration,
            finalURL: http.url,
            metrics: collector.makeMetrics(),
            receivedCookies: collector.receivedCookies + StoredCookie.fromResponse(http)
        )
    }
}
