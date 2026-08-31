import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum Inserter {
    /// Where a transcription ended up. Pasting needs Accessibility trust *and* a
    /// focused text field; when either is missing the text waits on the clipboard
    /// instead of being dropped.
    enum Outcome {
        case pasted
        case copied
        case clipboardUnavailable
    }

    // ⌘V is the only insertion path that works across native, web and Electron
    // text fields, so the text goes on the clipboard either way; the focused
    // element only decides whether we also press the keys.
    //
    // When the text is pasted the clipboard was only a transport, so its previous
    // contents go back afterwards. When it is left behind for the user to paste
    // themselves, the transcription is the delivery and stays put.
    static func insert(_ text: String, restoringClipboard: Bool) -> Outcome {
        let pasteboard = NSPasteboard.general
        let snapshot = restoringClipboard ? ClipboardSnapshot(pasteboard) : nil
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return .clipboardUnavailable }
        guard focusedElementAcceptsText() else { return .copied }
        let transcriptionChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .privateState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        if let snapshot {
            Task { @MainActor in
                // A synthetic ⌘V reports no completion, and the target app reads
                // the clipboard on its own schedule, so this waits long enough for
                // a slow Electron text field and no longer.
                try? await Task.sleep(for: .milliseconds(400))
                snapshot.restore(ifUnchangedFrom: transcriptionChangeCount)
            }
        }
        return .pasted
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

        /// Puts the contents back, unless the user copied something else in the
        /// meantime — their copy is newer and wins.
        func restore(ifUnchangedFrom changeCount: Int) {
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == changeCount else { return }
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

    // Native text controls. A search field is an AXTextField with the
    // AXSearchField subrole, so it needs no entry of its own.
    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String
    ]

    /// True when ⌘V would land somewhere. Returns false when the Accessibility
    /// API is unavailable, which is the right answer: posting the key event needs
    /// the same trust the query does.
    private static func focusedElementAcceptsText() -> Bool {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return false
        }
        let focusedElement = focusedValue as! AXUIElement

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focusedElement,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success, let role = roleValue as? String, textRoles.contains(role) {
            return true
        }

        // Web and Electron editors report generic roles (AXGroup, AXWebArea) and
        // refuse to make AXSelectedText settable, but they do publish a selection
        // range. A Finder icon or a game view publishes neither.
        var rangeValue: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success
    }
}
