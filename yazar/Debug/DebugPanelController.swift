#if DEBUG
import AppKit
import SwiftUI

/// Owns the small development window shared by all debug tools.
@MainActor
final class DebugPanelController: NSObject, NSWindowDelegate {
    private let yazar: Yazar
    private var panel: NSPanel?
    private var monitoringTask: Task<Void, Never>?

    init(yazar: Yazar) {
        self.yazar = yazar
        super.init()
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            startMonitoring()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Yazar Debug"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.center()

        let hostingView = NSHostingView(rootView: DebugPanelView(yazar: yazar))
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        self.panel = panel
        panel.orderFrontRegardless()
        startMonitoring()
    }

    func windowWillClose(_ notification: Notification) {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Polling exists only while the panel is open. Let delivery own AX while
    /// transcription is finishing, so diagnostics cannot delay the real capture.
    private func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    if !yazar.inputMonitor.isPaused, yazar.state != .transcribing, yazar.state != .retrying {
                        try await yazar.inputMonitor.refresh()
                    }
                    try await Task.sleep(for: .milliseconds(750))
                } catch {
                    return
                }
            }
        }
    }
}
#endif
