import Foundation

public enum TextSearch {
    /// Case-insensitive, non-overlapping matches as UTF-16 ranges (ready for NSTextView).
    public static func ranges(of query: String, in text: String, limit: Int = 10_000) -> [NSRange] {
        guard !query.isEmpty, !text.isEmpty else { return [] }
        let haystack = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: haystack.length)
        while ranges.count < limit {
            let found = haystack.range(of: query, options: .caseInsensitive, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            ranges.append(found)
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: haystack.length - next)
        }
        return ranges
    }
}
