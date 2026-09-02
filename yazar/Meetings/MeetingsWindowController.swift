import AppKit
import SwiftUI

/// Owns the meetings window.
///
/// Separate from the settings window rather than another page inside it: a
/// library is a list-detail browser that wants room, while `YazarView` is a
/// settings surface pinned to a narrow size range.
@MainActor
final class MeetingsWindowController: NSObject, NSWindowDelegate {
    private let store: MeetingStore
    private let session: MeetingSession
    private let notesMaker: MeetingNotesMaker
    private var window: NSWindow?

    init(store: MeetingStore, session: MeetingSession, notesMaker: MeetingNotesMaker) {
        self.store = store
        self.session = session
        self.notesMaker = notesMaker
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Meetings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 720, height: 420)
        window.center()

        let hostingView = NSHostingView(rootView: MeetingsView(store: store, session: session, notesMaker: notesMaker))
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.delegate = self

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
