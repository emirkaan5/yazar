import AppKit
import Observation
import SwiftUI

@main
struct YazarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Yazar", systemImage: appDelegate.menuBarIcon) {
            Button("Open Yazar") {
                appDelegate.showApp()
            }

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
    private var selectedPage = AppPage.general
    private var yazar: Yazar?
    private var overlayPanel: OverlayPanel?
    private var appWindow: NSWindow?

    override init() {
        super.init()
        permissions.refresh()
    }

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
        if permissions.readyToUse {
            startYazar()
        } else {
            showApp(page: .permissions)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        yazar?.stop()
    }

    func showApp(page: AppPage? = nil) {
        if let page {
            selectedPage = page
        }

        if let appWindow {
            appWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Yazar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        let hostingView = NSHostingView(
            rootView: YazarView(
                settings: settings,
                permissions: permissions,
                selection: Binding(
                    get: { [weak self] in self?.selectedPage ?? .general },
                    set: { [weak self] in self?.selectedPage = $0 }
                )
            )
        )
        hostingView.sizingOptions = [.minSize]
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        appWindow = window
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
