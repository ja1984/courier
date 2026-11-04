import AppKit
import CourierCore
import SwiftUI

/// Semantic colours (methods, status, syntax). Surfaces and accent come from the system.
enum Theme {
    // Surfaces
    static let content = Color(nsColor: dynamic(light: 0xFFFFFF, dark: 0x262626))
    static let success = Color(nsColor: dynamic(light: 0x007F31, dark: 0x4CC38A))

    // HTTP methods
    static let get = Color(nsColor: dynamic(light: 0x007F31, dark: 0x4CC38A))
    static let post = Color(nsColor: dynamic(light: 0xAD7A03, dark: 0xF5B83D))
    static let put = Color(nsColor: dynamic(light: 0x0053B8, dark: 0x5EA2FF))
    static let patch = Color(nsColor: dynamic(light: 0x623497, dark: 0xB48EF0))
    static let delete = Color(nsColor: dynamic(light: 0x8E1A10, dark: 0xF26B5B))
    static let options = Color(nsColor: dynamic(light: 0xA61468, dark: 0xF06CB4))
    static let otherMethod = Color(nsColor: dynamic(light: 0x6B6B6B, dark: 0xA0A0A0))

    // Code
    static let codeKey = dynamic(light: 0xA31515, dark: 0x9CDCFE)
    static let codeString = dynamic(light: 0x0451A5, dark: 0xCE9178)
    static let codeNumber = dynamic(light: 0x098658, dark: 0xB5CEA8)
    static let codeLiteral = dynamic(light: 0x0000FF, dark: 0x569CD6)
    static let codeTag = dynamic(light: 0x800000, dark: 0x569CD6)
    static let codeAttribute = dynamic(light: 0xE50000, dark: 0x9CDCFE)
    static let codeComment = dynamic(light: 0x008000, dark: 0x6A9955)

    // Search highlights (the system find colours: yellow for matches, orange for the current one)
    static let searchMatch = NSColor.systemYellow.withAlphaComponent(0.35)
    static let searchCurrent = NSColor.systemOrange.withAlphaComponent(0.6)

    nonisolated private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }

    nonisolated private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension HTTPMethod {
    var color: Color {
        switch self {
        case .get: Theme.get
        case .post: Theme.post
        case .put: Theme.put
        case .patch: Theme.patch
        case .delete: Theme.delete
        case .options: Theme.options
        case .head: Theme.get
        default: Theme.otherMethod
        }
    }
}

extension BodyKind {
    var title: String {
        switch self {
        case .none: "None"
        case .json: "JSON"
        case .text: "Text"
        case .form: "Form"
        }
    }
}

enum StatusStyle {
    static func color(for code: Int?) -> Color {
        guard let code else { return Theme.delete }
        switch code {
        case 200..<300: return Theme.success
        case 300..<400: return Theme.put
        case 400..<500: return Theme.post
        default: return Theme.delete
        }
    }
}

struct MethodLabel: View {
    let method: HTTPMethod
    var size: CGFloat = 10

    var body: some View {
        Text(method.rawValue)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(method.color)
    }
}

extension CollectionColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }

    /// A filled circle for menus, which draw SF Symbols in one color.
    var swatch: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return image
    }
}

/// The folder mark for a collection: its color, or secondary when it has none.
struct CollectionMark: View {
    let color: CollectionColor?
    var size: CGFloat = 10

    var body: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: size))
            .foregroundStyle(color.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
            .accessibilityHidden(true)
    }
}
