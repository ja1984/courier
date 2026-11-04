import AppKit
import SwiftUI

/// Installs an app-local NSEvent monitor while the view is on screen.
/// Return nil from the handler to swallow the event, or the event to let it through.
private struct LocalEventMonitor: ViewModifier {
    let mask: NSEvent.EventTypeMask
    let handler: (NSEvent) -> NSEvent?
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                let handler = handler
                // Local monitors run on the main thread, matching the handler's isolation.
                monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func onLocalEvent(matching mask: NSEvent.EventTypeMask, perform handler: @escaping (NSEvent) -> NSEvent?) -> some View {
        modifier(LocalEventMonitor(mask: mask, handler: handler))
    }
}
