import AppKit
import SwiftUI

/// The settings window's translucent backdrop. AppKit rather than a SwiftUI
/// material because only `.behindWindow` blending lets the desktop show
/// through; SwiftUI's materials blur what is inside the window. `.sidebar` is
/// the same material the page list draws, so the whole window reads as one
/// surface.
struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
