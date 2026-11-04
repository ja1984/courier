import Foundation

public struct TimingPhase: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable {
        /// Work done by the app before/after the network (shown muted).
        case local
        case network
    }

    public let name: String
    public let kind: Kind
    /// Offset from the start of the request.
    public let start: Duration
    public let duration: Duration

    public var id: String { name }
    public var end: Duration { start + duration }
}

public struct CertificateSummary: Equatable, Sendable {
    public var commonName: String?
    public var issuer: String?
    public var validUntil: Date?

    public init(commonName: String? = nil, issuer: String? = nil, validUntil: Date? = nil) {
        self.commonName = commonName
        self.issuer = issuer
        self.validUntil = validUntil
    }
}

/// Timestamps from URLSessionTaskTransactionMetrics, as plain values so they can be tested.
public struct TransactionTimestamps: Sendable {
    public var fetchStart: Date?
    public var domainLookupStart: Date?
    public var domainLookupEnd: Date?
    public var connectStart: Date?
    public var connectEnd: Date?
    public var secureConnectionStart: Date?
    public var secureConnectionEnd: Date?
    public var requestStart: Date?
    public var responseStart: Date?
    public var responseEnd: Date?

    public init(
        fetchStart: Date? = nil, domainLookupStart: Date? = nil, domainLookupEnd: Date? = nil,
        connectStart: Date? = nil, connectEnd: Date? = nil, secureConnectionStart: Date? = nil,
        secureConnectionEnd: Date? = nil, requestStart: Date? = nil, responseStart: Date? = nil,
        responseEnd: Date? = nil
    ) {
        self.fetchStart = fetchStart
        self.domainLookupStart = domainLookupStart
        self.domainLookupEnd = domainLookupEnd
        self.connectStart = connectStart
        self.connectEnd = connectEnd
        self.secureConnectionStart = secureConnectionStart
        self.secureConnectionEnd = secureConnectionEnd
        self.requestStart = requestStart
        self.responseStart = responseStart
        self.responseEnd = responseEnd
    }
}

public struct ResponseMetrics: Sendable {
    public var phases: [TimingPhase]
    public var httpVersion: String?
    public var localAddress: String?
    public var remoteAddress: String?
    public var tlsVersion: String?
    public var cipherSuite: String?
    public var certificate: CertificateSummary?
    public var isReusedConnection: Bool
    public var redirectCount: Int

    public var requestHeaderBytes: Int64
    public var requestBodyBytes: Int64
    public var responseHeaderBytes: Int64
    /// Body bytes as transferred (compressed, if the server compressed it).
    public var responseBodyBytes: Int64
    /// Body bytes after decompression.
    public var responseBodyDecodedBytes: Int64

    public init(
        phases: [TimingPhase] = [], httpVersion: String? = nil, localAddress: String? = nil,
        remoteAddress: String? = nil, tlsVersion: String? = nil, cipherSuite: String? = nil,
        certificate: CertificateSummary? = nil, isReusedConnection: Bool = false, redirectCount: Int = 0,
        requestHeaderBytes: Int64 = 0, requestBodyBytes: Int64 = 0, responseHeaderBytes: Int64 = 0,
        responseBodyBytes: Int64 = 0, responseBodyDecodedBytes: Int64 = 0
    ) {
        self.phases = phases
        self.httpVersion = httpVersion
        self.localAddress = localAddress
        self.remoteAddress = remoteAddress
        self.tlsVersion = tlsVersion
        self.cipherSuite = cipherSuite
        self.certificate = certificate
        self.isReusedConnection = isReusedConnection
        self.redirectCount = redirectCount
        self.requestHeaderBytes = requestHeaderBytes
        self.requestBodyBytes = requestBodyBytes
        self.responseHeaderBytes = responseHeaderBytes
        self.responseBodyBytes = responseBodyBytes
        self.responseBodyDecodedBytes = responseBodyDecodedBytes
    }

    public var total: Duration { phases.map(\.end).max() ?? .zero }
    public var requestBytes: Int64 { requestHeaderBytes + requestBodyBytes }
    public var responseBytes: Int64 { responseHeaderBytes + responseBodyBytes }
    public var isCompressed: Bool { responseBodyDecodedBytes > responseBodyBytes }

    public func appendingProcessing(_ duration: Duration) -> ResponseMetrics {
        var copy = self
        copy.phases.append(TimingPhase(name: "Process", kind: .local, start: total, duration: duration))
        return copy
    }

    /// Splits a transaction into Postman-style phases. Phases that didn't happen
    /// (e.g. DNS/TCP/TLS on a reused connection) are left out.
    public static func phases(from t: TransactionTimestamps, taskStart: Date) -> [TimingPhase] {
        var phases: [TimingPhase] = []
        func add(_ name: String, _ kind: TimingPhase.Kind = .network, from: Date?, to: Date?) {
            guard let from, let to, to >= from else { return }
            phases.append(TimingPhase(
                name: name,
                kind: kind,
                start: .seconds(max(0, from.timeIntervalSince(taskStart))),
                duration: .seconds(to.timeIntervalSince(from))
            ))
        }
        add("Prepare", .local, from: taskStart, to: t.fetchStart)
        add("Socket Initialization", from: t.fetchStart, to: t.domainLookupStart ?? t.connectStart ?? t.requestStart)
        add("DNS Lookup", from: t.domainLookupStart, to: t.domainLookupEnd)
        add("TCP Handshake", from: t.connectStart, to: t.secureConnectionStart ?? t.connectEnd)
        add("SSL Handshake", from: t.secureConnectionStart, to: t.secureConnectionEnd)
        add("Transfer Start", from: t.requestStart, to: t.responseStart)
        add("Download", from: t.responseStart, to: t.responseEnd)
        return phases
    }

    public static func httpVersion(fromProtocolName name: String?) -> String? {
        switch name?.lowercased() {
        case nil: nil
        case "h3", "http/3": "3"
        case "h2", "http/2": "2.0"
        case "http/1.1": "1.1"
        case "http/1.0": "1.0"
        case let other?: other
        }
    }

    public static func tlsVersionName(_ raw: UInt16) -> String {
        switch raw {
        case 0x0304: "TLSv1.3"
        case 0x0303: "TLSv1.2"
        case 0x0302: "TLSv1.1"
        case 0x0301: "TLSv1.0"
        default: String(format: "0x%04X", raw)
        }
    }

    public static func cipherSuiteName(_ raw: UInt16) -> String {
        let names: [UInt16: String] = [
            0x1301: "TLS_AES_128_GCM_SHA256",
            0x1302: "TLS_AES_256_GCM_SHA384",
            0x1303: "TLS_CHACHA20_POLY1305_SHA256",
            0xC02B: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
            0xC02C: "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
            0xC02F: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
            0xC030: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
            0xCCA8: "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256",
            0xCCA9: "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
            0xC009: "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
            0xC013: "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA",
            0x009C: "TLS_RSA_WITH_AES_128_GCM_SHA256",
            0x009D: "TLS_RSA_WITH_AES_256_GCM_SHA384",
        ]
        return names[raw] ?? String(format: "0x%04X", raw)
    }
}
