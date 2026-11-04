import Foundation

public struct HistoryGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let entries: [HistoryEntry]
}

public enum HistoryGrouping: String, CaseIterable, Sendable, Identifiable {
    case date, host

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .date: "Date"
        case .host: "Host"
        }
    }

    /// Groups entries (expected newest first). Groups are ordered by their most recent entry.
    public func groups(for entries: [HistoryEntry], calendar: Calendar = .current) -> [HistoryGroup] {
        var order: [String] = []
        var buckets: [String: (title: String, entries: [HistoryEntry])] = [:]
        for entry in entries {
            let (key, title) = bucket(for: entry, calendar: calendar)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = (title, [])
            }
            buckets[key]?.entries.append(entry)
        }
        return order.compactMap { key in
            buckets[key].map { HistoryGroup(id: "\(rawValue):\(key)", title: $0.title, entries: $0.entries) }
        }
    }

    private func bucket(for entry: HistoryEntry, calendar: Calendar) -> (key: String, title: String) {
        switch self {
        case .date:
            let day = calendar.startOfDay(for: entry.date)
            let title: String
            if calendar.isDateInToday(day) {
                title = "Today"
            } else if calendar.isDateInYesterday(day) {
                title = "Yesterday"
            } else {
                title = day.formatted(.dateTime.weekday(.wide).month().day())
            }
            return (String(day.timeIntervalSince1970), title)
        case .host:
            let host = entry.spec.hostLabel ?? "Other"
            return (host, host)
        }
    }
}

extension RequestSpec {
    /// Lowercased host with port when present (localhost:3000 and :8080 are different services).
    public var hostLabel: String? {
        var raw = url.trimmed
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        guard let parsed = URL(string: raw), let host = parsed.host()?.lowercased(), !host.isEmpty else { return nil }
        return parsed.port.map { "\(host):\($0)" } ?? host
    }
}
