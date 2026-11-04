import Foundation

public enum ResponseFormat: String, Sendable {
    case json, xml, html, text, binary

    public var title: String {
        switch self {
        case .json: "JSON"
        case .xml: "XML"
        case .html: "HTML"
        case .text: "Text"
        case .binary: "Binary"
        }
    }

    /// Whether this format has a pretty view distinct from raw.
    public var isFormattable: Bool {
        self == .json || self == .xml || self == .html
    }

    /// Picks the format from the Content-Type header, falling back to sniffing the body.
    public static func detect(contentType: String?, text: String?) -> ResponseFormat {
        guard let text else { return .binary }
        if let type = contentType?.lowercased() {
            if type.contains("json") { return .json }
            if type.contains("html") { return .html }
            if type.contains("xml") { return .xml }
        }
        let head = text.drop { $0.isWhitespace }.prefix(64).lowercased()
        if head.hasPrefix("{") || head.hasPrefix("["), JSONFormatter.isValid(text) { return .json }
        if head.hasPrefix("<!doctype html") || head.hasPrefix("<html") { return .html }
        if head.hasPrefix("<?xml") { return .xml }
        return .text
    }

    /// Returns a re-indented version of `text`, or nil if it can't be parsed as this format.
    public func prettyPrinted(_ text: String) -> String? {
        switch self {
        case .json:
            return JSONFormatter.prettyPrinted(text)
        case .xml:
            // Validate with the XML parser, but format ourselves so content isn't rewritten.
            guard (try? XMLDocument(xmlString: text, options: [])) != nil else { return nil }
            return MarkupFormatter.prettyPrinted(text, isHTML: false)
        case .html:
            // Real-world HTML is rarely well-formed, so it's never rejected.
            return MarkupFormatter.prettyPrinted(text, isHTML: true)
        case .text, .binary:
            return nil
        }
    }
}
