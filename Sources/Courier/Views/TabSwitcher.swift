import SwiftUI

/// Plain text tabs with a soft pill behind the selected one, as in Keychain Access and other
/// macOS 26 apps. Used to switch what's shown below; settings keep standard segmented controls.
struct TabSwitcher<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        var help: String?
    }

    @Binding var selection: Value
    let items: [Item]
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                TabSwitcherButton(
                    title: item.title,
                    isSelected: item.value == selection,
                    isEnabled: isEnabled
                ) {
                    selection = item.value
                }
                .help(item.help ?? "")
            }
        }
        .fixedSize()
    }
}

private struct TabSwitcherButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    private var fill: Color {
        if isSelected { return Color.primary.opacity(isEnabled ? 0.09 : 0.05) }
        return Color.primary.opacity(isHovering && isEnabled ? 0.05 : 0)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isEnabled ? (isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)) : AnyShapeStyle(.tertiary))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(fill))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
