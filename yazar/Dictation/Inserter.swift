import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum Inserter {
    /// Whether the transcription reached its reliable delivery destination.
    enum Outcome {
        /// The transcription is on the clipboard. Command-V may also have been
        /// posted, but the inserter cannot confirm that the target consumed it.
        case delivered
        /// The inserter could not place the transcription on the clipboard.
        case clipboardUnavailable
    }

    // The clipboard is the delivery guarantee. Command-V is a best-effort
    // convenience because CGEvent cannot report whether the target consumed it.
    static func insert(_ text: String) -> Outcome {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore()
            return .clipboardUnavailable
        }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return .delivered }

        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return .delivered
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .delivered
    }

    /// A copy of the pasteboard's concrete contents.
    ///
    /// Items whose data is promised rather than present — file promises, some
    /// app-provided types — cannot be reproduced and are dropped. That is still
    /// strictly better than the previous behaviour, which dropped everything.
    private struct ClipboardSnapshot {
        private let items: [[NSPasteboard.PasteboardType: Data]]

        init(_ pasteboard: NSPasteboard) {
            items = (pasteboard.pasteboardItems ?? []).map { item in
                item.types.reduce(into: [:]) { contents, type in
                    contents[type] = item.data(forType: type)
                }
            }
        }

        /// Puts the previous contents back after a clipboard write fails.
        func restore() {
            let pasteboard = NSPasteboard.general
            let restored = items.map { contents in
                let item = NSPasteboardItem()
                for (type, data) in contents {
                    item.setData(data, forType: type)
                }
                return item
            }
            pasteboard.clearContents()
            guard !restored.isEmpty else { return }
            pasteboard.writeObjects(restored)
        }
    }
}
