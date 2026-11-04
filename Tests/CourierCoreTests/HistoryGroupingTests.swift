import Foundation
import Testing
@testable import CourierCore

@Suite struct HistoryGroupingTests {
    private func entry(_ url: String, _ date: Date) -> HistoryEntry {
        HistoryEntry(date: date, spec: RequestSpec(url: url))
    }

    @Test func groupsByHostInMostRecentOrder() {
        let now = Date()
        let entries = [
            entry("https://API.example.com/a", now),
            entry("localhost:3000/x", now.addingTimeInterval(-10)),
            entry("https://api.example.com/b", now.addingTimeInterval(-20)),
            entry("http://localhost:8080/y", now.addingTimeInterval(-30)),
            entry("not a url ::", now.addingTimeInterval(-40)),
        ]
        let groups = HistoryGrouping.host.groups(for: entries)
        #expect(groups.map(\.title) == ["api.example.com", "localhost:3000", "localhost:8080", "Other"])
        #expect(groups[0].entries.map(\.spec.url) == ["https://API.example.com/a", "https://api.example.com/b"])
    }

    @Test func groupsByDay() throws {
        let calendar = Calendar.current
        let now = Date()
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let groups = HistoryGrouping.date.groups(for: [entry("a.com", now), entry("b.com", now), entry("c.com", yesterday)])
        #expect(groups.map(\.title) == ["Today", "Yesterday"])
        #expect(groups.map(\.entries.count) == [2, 1])
        // Ids are unique across groupings so collapse state doesn't leak between modes.
        #expect(Set(groups.map(\.id)).isDisjoint(with: HistoryGrouping.host.groups(for: groups[0].entries).map(\.id)))
    }
}
