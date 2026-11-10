import Foundation
import Security
import Synchronization

/// How cookies follow redirects: cookies set by each hop join the jar's, and the request's
/// own cookies only go to the host they were written for.
struct RedirectCookies: Sendable {
    var jar: CookieJar?
    var requestCookies: [CookiePair]
    var originalHost: String?

    /// The Cookie header for the next hop, given the cookies received so far.
    func header(for url: URL, received: [StoredCookie], at now: Date = Date()) -> String? {
        var working = jar ?? CookieJar()
        working.store(received, at: now)
        let ownCookies = url.host()?.lowercased() == originalHost?.lowercased() ? requestCookies : []
        return CookieJar.cookieHeader(jar: working.cookies(for: url, at: now), request: ownCookies)
    }
}

/// URLSession delegate that captures task metrics and the server's certificate,
/// and carries cookies across redirects.
final class MetricsCollector: NSObject, URLSessionTaskDelegate, Sendable {
    private struct State {
        var metrics: URLSessionTaskMetrics?
        var certificate: CertificateSummary?
        var receivedCookies: [StoredCookie] = []
    }

    private let state = Mutex(State())
    private let cookies: RedirectCookies

    init(cookies: RedirectCookies = RedirectCookies(requestCookies: [])) {
        self.cookies = cookies
    }

    /// Cookies set by redirect responses (the final response's are read separately).
    var receivedCookies: [StoredCookie] { state.withLock { $0.receivedCookies } }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        let received = state.withLock { state in
            state.receivedCookies += StoredCookie.fromResponse(response)
            return state.receivedCookies
        }
        var next = request
        next.httpShouldHandleCookies = false
        if let url = request.url {
            next.setValue(cookies.header(for: url, received: received), forHTTPHeaderField: "Cookie")
        }
        return next
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        state.withLock { $0.metrics = metrics }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // Only observe; trust evaluation stays with the system.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            let summary = Self.certificateSummary(from: trust)
            state.withLock { $0.certificate = summary }
        }
        return (.performDefaultHandling, nil)
    }

    func makeMetrics() -> ResponseMetrics? {
        let (taskMetrics, certificate) = state.withLock { ($0.metrics, $0.certificate) }
        guard let taskMetrics else { return nil }
        // Ignore cache lookups etc.; the last network transaction is the final response.
        let transactions = taskMetrics.transactionMetrics.filter { $0.resourceFetchType == .networkLoad }
        guard let last = transactions.last else { return nil }

        let timestamps = TransactionTimestamps(
            fetchStart: last.fetchStartDate,
            domainLookupStart: last.domainLookupStartDate,
            domainLookupEnd: last.domainLookupEndDate,
            connectStart: last.connectStartDate,
            connectEnd: last.connectEndDate,
            secureConnectionStart: last.secureConnectionStartDate,
            secureConnectionEnd: last.secureConnectionEndDate,
            requestStart: last.requestStartDate,
            responseStart: last.responseStartDate,
            responseEnd: last.responseEndDate
        )
        // With redirects, measure the final hop from its own start.
        let taskStart = transactions.count > 1 ? (last.fetchStartDate ?? taskMetrics.taskInterval.start) : taskMetrics.taskInterval.start

        return ResponseMetrics(
            phases: ResponseMetrics.phases(from: timestamps, taskStart: taskStart),
            httpVersion: ResponseMetrics.httpVersion(fromProtocolName: last.networkProtocolName),
            localAddress: Self.address(last.localAddress, last.localPort),
            remoteAddress: Self.address(last.remoteAddress, last.remotePort),
            tlsVersion: last.negotiatedTLSProtocolVersion.map { ResponseMetrics.tlsVersionName($0.rawValue) },
            cipherSuite: last.negotiatedTLSCipherSuite.map { ResponseMetrics.cipherSuiteName($0.rawValue) },
            certificate: last.negotiatedTLSProtocolVersion == nil ? nil : certificate,
            isReusedConnection: last.isReusedConnection,
            redirects: RedirectHop.chain(from: transactions.compactMap(Self.hop)),
            requestHeaderBytes: last.countOfRequestHeaderBytesSent,
            requestBodyBytes: last.countOfRequestBodyBytesSent,
            responseHeaderBytes: last.countOfResponseHeaderBytesReceived,
            responseBodyBytes: last.countOfResponseBodyBytesReceived,
            responseBodyDecodedBytes: last.countOfResponseBodyBytesAfterDecoding
        )
    }

    /// A transaction as a hop candidate; `RedirectHop.chain` decides which ones were redirects.
    private static func hop(_ t: URLSessionTaskTransactionMetrics) -> RedirectHop? {
        guard let url = t.request.url, let response = t.response as? HTTPURLResponse else { return nil }
        var duration: Duration?
        if let start = t.fetchStartDate, let end = t.responseEndDate, end >= start {
            duration = .seconds(end.timeIntervalSince(start))
        }
        return RedirectHop(
            method: t.request.httpMethod ?? "GET",
            url: url,
            statusCode: response.statusCode,
            location: response.value(forHTTPHeaderField: "Location"),
            httpVersion: ResponseMetrics.httpVersion(fromProtocolName: t.networkProtocolName),
            duration: duration
        )
    }

    private static func address(_ host: String?, _ port: Int?) -> String? {
        guard let host else { return nil }
        guard let port else { return host }
        return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    private static func certificateSummary(from trust: SecTrust) -> CertificateSummary? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return nil
        }
        var commonName: CFString?
        SecCertificateCopyCommonName(leaf, &commonName)

        let keys = [kSecOIDX509V1IssuerName, kSecOIDX509V1ValidityNotAfter] as CFArray
        let values = SecCertificateCopyValues(leaf, keys, nil) as? [String: Any]

        var issuer: String?
        if let issuerEntry = values?[kSecOIDX509V1IssuerName as String] as? [String: Any],
           let parts = issuerEntry[kSecPropertyKeyValue as String] as? [[String: Any]] {
            let label = { (oid: CFString) in
                parts.first { ($0[kSecPropertyKeyLabel as String] as? String) == oid as String }?[kSecPropertyKeyValue as String] as? String
            }
            issuer = label(kSecOIDCommonName) ?? label(kSecOIDOrganizationName)
        }

        var validUntil: Date?
        if let entry = values?[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
           let seconds = entry[kSecPropertyKeyValue as String] as? NSNumber {
            validUntil = Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
        }
        return CertificateSummary(commonName: commonName as String?, issuer: issuer, validUntil: validUntil)
    }
}
