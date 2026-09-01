import AppKit
import Observation
import SwiftUI

@MainActor
final class OverlayPanel {
    private let yazar: Yazar
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    init(yazar: Yazar) {
        self.yazar = yazar
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: OverlayView.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let hostingView = NSHostingView(rootView: OverlayView(yazar: yazar))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        observeState()
    }

    private func observeState() {
        withObservationTracking {
            _ = yazar.state
        } onChange: { [unowned self] in
            Task { @MainActor [unowned self] in
                self.updateVisibility()
                self.observeState()
            }
        }
    }

    private func updateVisibility() {
        if yazar.state == .idle {
            hideTask?.cancel()
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(OverlayView.capsuleAnimationDuration))
                guard !Task.isCancelled, let self, self.yazar.state == .idle else { return }
                self.panel.orderOut(nil)
                self.hideTask = nil
            }
            return
        }

        hideTask?.cancel()
        hideTask = nil

        // Position once per session. State changes while recording (warmingUp ->
        // recording -> transcribing) must not move the panel out from under the
        // entrance animation, and the mouse may have crossed to another screen.
        guard !panel.isVisible else { return }
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 48
        )
        panel.setFrameOrigin(origin)
    }
}
