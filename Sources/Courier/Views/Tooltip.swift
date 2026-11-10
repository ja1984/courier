import AppKit
import SwiftUI

extension View {
    /// A tooltip that shows after a short hover (instead of the system's ~1.5 s), as a small
    /// bubble with the keyboard shortcut set apart: "Copy as cURL (⇧⌘C)" shows "⇧⌘C" as a key cap.
    /// It follows text changes while visible, so a button can switch it to "Copied".
    /// Use it for buttons and controls; long descriptive help on rows is better left to `.help`.
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}

private struct TooltipModifier: ViewModifier {
    let text: String
    @State private var anchor = TooltipAnchor()
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(TooltipAnchorView(anchor: anchor))
            .onHover { isHovering = $0 }
            .task(id: isHovering) {
                guard isHovering, !text.isEmpty else {
                    TooltipPanel.shared.hide(owner: anchor)
                    return
                }
                try? await Task.sleep(for: TooltipPanel.shared.delay)
                guard !Task.isCancelled, isHovering else { return }
                TooltipPanel.shared.show(text, for: anchor)
            }
            .onChange(of: text) {
                guard isHovering else { return }
                if text.isEmpty { TooltipPanel.shared.hide(owner: anchor) } else { TooltipPanel.shared.show(text, for: anchor) }
            }
            .onDisappear { TooltipPanel.shared.hide(owner: anchor) }
            .accessibilityHint(text)
    }
}

/// Holds the AppKit view behind the SwiftUI view, to find where it is on screen.
private final class TooltipAnchor {
    weak var view: NSView?
}

private struct TooltipAnchorView: NSViewRepresentable {
    let anchor: TooltipAnchor

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }

    /// Never takes clicks or hover from the view it sits behind.
    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// One borderless, click-through panel shared by all tooltips.
private final class TooltipPanel {
    static let shared = TooltipPanel()

    private let panel: NSPanel
    private let host = NSHostingView(rootView: TooltipBubble(text: ""))
    private weak var owner: TooltipAnchor?
    private var hiddenAt = Date.distantPast

    /// Like macOS: once a tooltip has been showing, moving to the next control shows its tooltip at once.
    var delay: Duration {
        owner != nil || Date().timeIntervalSince(hiddenAt) < 0.6 ? .milliseconds(40) : .milliseconds(300)
    }

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.contentView = host
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideNow() }
        }
    }

    func show(_ text: String, for anchor: TooltipAnchor) {
        guard let view = anchor.view, let window = view.window, window.isVisible else { return }
        owner = anchor
        host.rootView = TooltipBubble(text: text)
        panel.appearance = window.effectiveAppearance
        let size = host.fittingSize
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .infinite

        // Centered below the control, or above it when there's no room below.
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - 6 - size.height)
        if origin.y < screen.minY { origin.y = rect.maxY + 6 }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide(owner anchor: TooltipAnchor) {
        guard owner === anchor else { return }
        hideNow()
    }

    private func hideNow() {
        guard owner != nil || panel.isVisible else { return }
        owner = nil
        hiddenAt = Date()
        panel.orderOut(nil)
    }
}

private struct TooltipBubble: View {
    let text: String

    /// Splits "Copy as cURL (⇧⌘C)" into the label and the shortcut.
    private var parts: (label: String, shortcut: String?) {
        guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else { return (text, nil) }
        let inner = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
        let isShortcut = inner == "Esc" || inner.contains(where: { "⌘⇧⌥⌃".contains($0) })
        guard isShortcut else { return (text, nil) }
        return (text[..<open].trimmingCharacters(in: .whitespaces), inner)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(parts.label)
            if let shortcut = parts.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}
