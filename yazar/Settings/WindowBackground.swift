import AppKit
import SwiftUI

/// The settings window's translucent backdrop. AppKit rather than a SwiftUI
/// material because only `.behindWindow` blending lets the desktop show
/// through; SwiftUI's materials blur what is inside the window.
/// `.underWindowBackground` is the thinnest of the behind-window materials, so
/// the desktop reads through the whole window as one surface.
struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
