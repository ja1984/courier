import Foundation
import Testing
@testable import CourierCore

@Suite struct ResponseMetricsTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    private func at(_ ms: Double) -> Date { t0.addingTimeInterval(ms / 1000) }

    @Test func fullConnectionPhases() {
        let timestamps = TransactionTimestamps(
            fetchStart: at(2), domainLookupStart: at(400), domainLookupEnd: at(430),
            connectStart: at(430), connectEnd: at(480), secureConnectionStart: at(450),
            secureConnectionEnd: at(480), requestStart: at(481), responseStart: at(660), responseEnd: at(700)
        )
        let phases = ResponseMetrics.phases(from: timestamps, taskStart: t0)
        #expect(phases.map(\.name) == [
            "Prepare", "Socket Initialization", "DNS Lookup", "TCP Handshake", "SSL Handshake", "Transfer Start", "Download",
        ])
        #expect(phases.first?.kind == .local)
        let tcp = phases[3]
        #expect(abs((tcp.duration / .milliseconds(1)) - 20) < 0.001) // connectStart -> secureConnectionStart
        #expect(abs((phases[2].start / .milliseconds(1)) - 400) < 0.001)

        let metrics = ResponseMetrics(phases: phases).appendingProcessing(.milliseconds(3))
        #expect(metrics.phases.last?.name == "Process")
        #expect(abs((metrics.total / .milliseconds(1)) - 703) < 0.001)
    }

    @Test func reusedConnectionSkipsHandshakes() {
        let timestamps = TransactionTimestamps(fetchStart: at(0), requestStart: at(1), responseStart: at(50), responseEnd: at(60))
        let names = ResponseMetrics.phases(from: timestamps, taskStart: t0).map(\.name)
        #expect(names == ["Prepare", "Socket Initialization", "Transfer Start", "Download"])
    }

    @Test func plainHTTPHasNoSSLPhase() throws {
        let timestamps = TransactionTimestamps(
            fetchStart: at(0), connectStart: at(1), connectEnd: at(5), requestStart: at(5), responseStart: at(9), responseEnd: at(10)
        )
        let phases = ResponseMetrics.phases(from: timestamps, taskStart: t0)
        #expect(!phases.map(\.name).contains("SSL Handshake"))
        let tcp = try #require(phases.first { $0.name == "TCP Handshake" })
        #expect(abs((tcp.duration / .milliseconds(1)) - 4) < 0.001)
    }

    @Test func names() {
        #expect(ResponseMetrics.httpVersion(fromProtocolName: "h2") == "2.0")
        #expect(ResponseMetrics.httpVersion(fromProtocolName: "http/1.1") == "1.1")
        #expect(ResponseMetrics.httpVersion(fromProtocolName: "h3") == "3")
        #expect(ResponseMetrics.tlsVersionName(0x0304) == "TLSv1.3")
        #expect(ResponseMetrics.cipherSuiteName(0x1301) == "TLS_AES_128_GCM_SHA256")
        #expect(ResponseMetrics.cipherSuiteName(0xABCD) == "0xABCD")
    }

    @Test func sizes() {
        let metrics = ResponseMetrics(
            requestHeaderBytes: 268, responseHeaderBytes: 1_160, responseBodyBytes: 31_920, responseBodyDecodedBytes: 157_780
        )
        #expect(metrics.requestBytes == 268)
        #expect(metrics.responseBytes == 33_080)
        #expect(metrics.isCompressed)
    }

    @Test func statusExplanations() {
        #expect(HTTPStatus.explanation(for: 200).hasPrefix("Standard response"))
        #expect(HTTPStatus.explanation(for: 299).contains("accepted"))
    }
}
