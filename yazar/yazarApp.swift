import AppKit
import Observation
import SwiftUI

@main
struct YazarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Yazar", systemImage: appDelegate.menuBarIcon) {
            Button("Settings…") {
                appDelegate.showSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit Yazar") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let permissions = Permissions()
    private var yazar: Yazar?
    private var overlayPanel: OverlayPanel?
    private var settingsWindow: NSWindow?

    var menuBarIcon: String {
        guard let yazar else { return "waveform" }
        return switch yazar.state {
        case .idle, .noSpeech: "waveform"
        case .warmingUp, .recording: "waveform.circle.fill"
        case .transcribing: "ellipsis.circle"
        case .error: "exclamationmark.circle"
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        permissions.refresh()

        if permissions.allGranted && permissions.fnConfigured {
            startYazar()
        } else {
            showSettings(page: .permissions)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        yazar?.stop()
    }

    func showSettings(page: SettingsPage = .general) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Yazar Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 680, height: 420)
        window.isReleasedWhenClosed = false
        window.center()
        let hostingView = NSHostingView(
            rootView: SettingsView(settings: settings, permissions: permissions, selection: page)
        )
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func startYazar() {
        guard yazar == nil else { return }
        let yazar = Yazar(settings: settings)
        let panel = OverlayPanel(yazar: yazar)
        self.yazar = yazar
        overlayPanel = panel

        do {
            try yazar.start()
        } catch {
            yazar.show(error: error)
        }
    }
}
