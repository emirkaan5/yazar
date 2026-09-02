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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings: Settings
    private let permissions = Permissions()
    private let yazar: Yazar
    private let composer: NotesComposer
    private var selectedPage = AppPage.dictation
    private var overlayPanel: OverlayPanel?
    private var appWindow: NSWindow?

    override init() {
        let settings = Settings()
        self.settings = settings
        yazar = Yazar(settings: settings)
        composer = NotesComposer(settings: settings)
        super.init()
        permissions.refresh()
    }

    var menuBarIcon: String {
        switch yazar.state {
        case .idle, .noSpeech: "waveform"
        case .warmingUp, .recording: "waveform.circle.fill"
        case .transcribing: "ellipsis.circle"
        case .error: "exclamationmark.circle"
        }
    }

    /// The system requirements for the trigger selected right now. Keeping this
    /// beside engine startup means polling only has to publish system state.
    private var isReadyToStart: Bool {
        permissions.allGranted &&
            (!settings.dictationTrigger.usesFn || permissions.fnConfigured)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isReadyToStart {
            startEngine()
        } else {
            showApp(page: .systemAccess)
            permissions.startPolling()
            startEngineWhenReady()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        yazar.stop()
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
            contentRect: NSRect(origin: .zero, size: YazarView.minimumSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Yazar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenDisallowsTiling)
        window.center()
        let hostingView = NSHostingView(
            rootView: YazarView(
                settings: settings,
                permissions: permissions,
                yazar: yazar,
                composer: composer,
                selection: Binding(
                    get: { [weak self] in self?.selectedPage ?? .dictation },
                    set: { [weak self] in self?.selectedPage = $0 }
                )
            )
        )
        hostingView.sizingOptions = [.minSize]
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.maxSize = maximumFrameSize(for: window)
        window.delegate = self
        appWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let maximumSize = maximumFrameSize(for: sender)
        return NSSize(
            width: min(frameSize.width, maximumSize.width),
            height: min(frameSize.height, maximumSize.height)
        )
    }

    private func maximumFrameSize(for window: NSWindow) -> NSSize {
        window.frameRect(
            forContentRect: NSRect(origin: .zero, size: YazarView.maximumSize)
        ).size
    }

    /// Builds the overlay once and claims the hot key. Safe to call again after a
    /// failed attempt, since HotKey.start() is a no-op once the tap exists.
    private func startEngine() {
        permissions.stopPolling()
        if overlayPanel == nil {
            overlayPanel = OverlayPanel(yazar: yazar, settings: settings)
        }
        do {
            try yazar.start()
        } catch {
            yazar.show(.hotKey(error))
        }
    }

    /// Grants can land while Yazar is already running, so the engine starts in
    /// place rather than making the user relaunch. The Relaunch button on the
    /// permissions screen stays as the fallback for when the tap still fails.
    private func startEngineWhenReady() {
        withObservationTracking {
            _ = isReadyToStart
        } onChange: { [weak self] in
            // onChange fires before the new value lands, so re-read on the main actor.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if isReadyToStart {
                    startEngine()
                } else {
                    startEngineWhenReady()
                }
            }
        }
    }
}
