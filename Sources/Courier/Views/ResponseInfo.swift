import CourierCore
import SwiftUI

/// A header item ("Time: 715 ms") that opens a details popover when clicked.
private struct InfoItem<Label: View, Details: View>: View {
    let help: String
    @ViewBuilder let label: () -> Label
    @ViewBuilder let details: () -> Details
    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
                .font(.system(size: 12))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(isHovering || isPresented ? 0.07 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            details()
                .padding(16)
        }
    }
}

private func formatBytes(_ bytes: Int64) -> String {
    bytes < 1_000 ? "\(bytes) B" : bytes.formatted(.byteCount(style: .file))
}

private func formatMs(_ duration: Duration) -> String {
    String(format: "%.2f ms", duration / .milliseconds(1))
}

private struct LabeledLine: View {
    let label: String
    let value: String
    var muted = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text(label).foregroundStyle(muted ? .tertiary : .secondary)
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(muted ? .secondary : .primary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: muted ? 11 : 12))
    }
}

// MARK: - Items

struct ResponseInfoBar: View {
    let response: HTTPResponse

    var body: some View {
        HStack(spacing: 2) {
            if let metrics = response.metrics {
                NetworkItem(metrics: metrics, isSecure: response.finalURL?.scheme == "https")
            }
            StatusItem(code: response.statusCode, text: response.statusText)
            TimeItem(response: response)
            SizeItem(response: response)
        }
    }
}

private struct NetworkItem: View {
    let metrics: ResponseMetrics
    let isSecure: Bool

    var body: some View {
        InfoItem(help: "Network details") {
            Image(systemName: isSecure ? "lock.shield" : "network")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Network details")
        } details: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Network").font(.headline)
                LabeledLine(label: "HTTP Version", value: metrics.httpVersion ?? "—")
                LabeledLine(label: "Local Address", value: metrics.localAddress ?? "—")
                LabeledLine(label: "Remote Address", value: metrics.remoteAddress ?? "—")
                if metrics.redirectCount > 0 {
                    LabeledLine(label: "Redirects", value: "\(metrics.redirectCount) (details are for the final hop)")
                }
                if metrics.tlsVersion != nil {
                    Divider()
                    LabeledLine(label: "TLS Protocol", value: metrics.tlsVersion ?? "—")
                    LabeledLine(label: "Cipher Name", value: metrics.cipherSuite ?? "—")
                }
                if let certificate = metrics.certificate {
                    Divider()
                    LabeledLine(label: "Certificate CN", value: certificate.commonName ?? "—")
                    LabeledLine(label: "Issuer", value: certificate.issuer ?? "—")
                    LabeledLine(
                        label: "Valid Until",
                        value: certificate.validUntil?.formatted(date: .abbreviated, time: .standard) ?? "—"
                    )
                }
            }
            .frame(width: 360)
        }
    }
}

private struct StatusItem: View {
    let code: Int
    let text: String

    var body: some View {
        let color = StatusStyle.color(for: code)
        InfoItem(help: "What \(code) means") {
            HStack(spacing: 4) {
                Text("Status:").foregroundStyle(.secondary)
                Text("\(code) \(text)").foregroundStyle(color).fontWeight(.medium)
            }
        } details: {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(code) \(text)").font(.headline)
                Divider()
                Text(HTTPStatus.explanation(for: code))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 300, alignment: .leading)
        }
    }
}

private struct TimeItem: View {
    let response: HTTPResponse

    var body: some View {
        InfoItem(help: "Timing breakdown") {
            HStack(spacing: 4) {
                Text("Time:").foregroundStyle(.secondary)
                Text("\(response.durationMs) ms").foregroundStyle(Theme.success).fontWeight(.medium)
            }
        } details: {
            if let metrics = response.metrics, !metrics.phases.isEmpty {
                TimingWaterfall(metrics: metrics)
            } else {
                Text("No timing details were reported for this request.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 260)
            }
        }
    }
}

private struct TimingWaterfall: View {
    let metrics: ResponseMetrics
    private let barWidth: CGFloat = 200

    var body: some View {
        let total = max(metrics.total / .milliseconds(1), 0.001)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EVENT")
                Spacer()
                Text("TIME")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            ForEach(metrics.phases) { phase in
                let isLocal = phase.kind == .local
                HStack(spacing: 12) {
                    Text(phase.name)
                        .frame(width: 140, alignment: .leading)
                        .foregroundStyle(isLocal ? .tertiary : .primary)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 18)
                        if !isLocal {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.success.gradient)
                                .frame(width: max(2, barWidth * (phase.duration / .milliseconds(1)) / total), height: 12)
                                .offset(x: barWidth * (phase.start / .milliseconds(1)) / total)
                        }
                    }
                    .frame(width: barWidth, alignment: .leading)
                    Text(formatMs(phase.duration))
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle(isLocal ? .tertiary : .primary)
                }
                .font(.system(size: 12))
                .padding(.vertical, isLocal ? 6 : 3)
                .accessibilityElement(children: .combine)
            }

            Divider().padding(.vertical, 8)
            HStack {
                Text("Total").fontWeight(.semibold)
                Spacer()
                Text(formatMs(metrics.total)).monospacedDigit().fontWeight(.semibold)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.success)
            if metrics.isReusedConnection {
                Text("Connection was reused, so DNS, TCP and SSL didn't happen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .frame(width: 450)
    }
}

private struct SizeItem: View {
    let response: HTTPResponse

    var body: some View {
        InfoItem(help: "Size breakdown") {
            HStack(spacing: 4) {
                Text("Size:").foregroundStyle(.secondary)
                Text(formatBytes(response.transferSize)).foregroundStyle(Theme.success).fontWeight(.medium)
            }
        } details: {
            VStack(alignment: .leading, spacing: 8) {
                if let metrics = response.metrics {
                    SizeSection(
                        title: "Response Size", systemImage: "arrow.down", tint: .accentColor,
                        total: metrics.responseBytes, headers: metrics.responseHeaderBytes, bodyBytes: metrics.responseBodyBytes,
                        uncompressed: metrics.isCompressed ? metrics.responseBodyDecodedBytes : nil
                    )
                    Divider().padding(.vertical, 4)
                    SizeSection(
                        title: "Request Size", systemImage: "arrow.up", tint: .orange,
                        total: metrics.requestBytes, headers: metrics.requestHeaderBytes, bodyBytes: metrics.requestBodyBytes,
                        uncompressed: nil
                    )
                    Divider().padding(.vertical, 4)
                    Text("All size calculations are approximate")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    LabeledLine(label: "Body", value: formatBytes(Int64(response.body.count)))
                }
            }
            .frame(width: 280)
        }
    }
}

private struct SizeSection: View {
    let title: String
    let systemImage: String
    let tint: Color
    let total: Int64
    let headers: Int64
    let bodyBytes: Int64
    let uncompressed: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.15)))
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(formatBytes(total)).fontWeight(.semibold)
            }
            .font(.system(size: 12))
            Group {
                LabeledLine(label: "Headers", value: formatBytes(headers))
                LabeledLine(label: "Body", value: formatBytes(bodyBytes))
                if let uncompressed {
                    LabeledLine(label: "Uncompressed", value: formatBytes(uncompressed), muted: true)
                }
            }
            .padding(.leading, 26)
        }
    }
}
