#if DEBUG
import AppKit
import SwiftUI

/// Owns the small development window shared by all debug tools.
@MainActor
final class DebugPanelController {
    private let yazar: Yazar
    private var panel: NSPanel?

    init(yazar: Yazar) {
        self.yazar = yazar
    }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 230),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Yazar Debug"
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.center()

        let hostingView = NSHostingView(rootView: DebugPanelView(yazar: yazar))
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
#endif
