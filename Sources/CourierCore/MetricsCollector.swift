import Foundation
import Security
import Synchronization

/// URLSession delegate that captures task metrics and the server's certificate.
final class MetricsCollector: NSObject, URLSessionTaskDelegate, Sendable {
    private struct State {
        var metrics: URLSessionTaskMetrics?
        var certificate: CertificateSummary?
    }

    private let state = Mutex(State())

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
