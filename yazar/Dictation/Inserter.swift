import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum Inserter {
    /// What the inserter can report synchronously. Posting Command-V does not
    /// confirm that the focused application consumed it.
    enum Outcome {
        /// Command-V was posted to a target AX identifies as editable.
        case pasteAttempted
        /// The transcription remains current on the clipboard. Command-V may
        /// also have been posted when target evidence was inconclusive.
        case copied
        case clipboardUnavailable
    }

    // ⌘V is the only insertion path that works across native, web and Electron
    // text fields as well as custom-rendered editors, so the text goes on the
    // clipboard either way. AX metadata can identify some editable controls but
    // cannot rule out custom ones, so missing evidence never blocks the shortcut.
    //
    // Positive target evidence makes best-effort restoration reasonable. When
    // the target is unknown, the transcription stays available for manual paste
    // whether or not the application consumed the synthetic shortcut.
    static func insert(_ text: String, restoringClipboard: Bool) -> Outcome {
        let hasEditableTargetEvidence = focusedElementProvidesTextEvidence()
        let pasteboard = NSPasteboard.general
        let snapshot = restoringClipboard ? ClipboardSnapshot(pasteboard) : nil
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot?.restore()
            return .clipboardUnavailable
        }
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { return .copied }
        let transcriptionChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return .copied
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        guard hasEditableTargetEvidence else { return .copied }

        if let snapshot {
            Task { @MainActor in
                // A synthetic ⌘V reports no completion, and the target app reads
                // the clipboard on its own schedule, so this waits long enough for
                // a slow Electron text field and no longer.
                try? await Task.sleep(for: .milliseconds(400))
                snapshot.restore(ifUnchangedFrom: transcriptionChangeCount)
            }
        }
        return .pasteAttempted
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
            restore(to: pasteboard)
        }

        /// Puts the contents back without a change-count check. Use this when a
        /// clipboard write has already failed synchronously.
        func restore() {
            restore(to: .general)
        }

        private func restore(to pasteboard: NSPasteboard) {
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

    /// Positive evidence that the focused AX element represents editable text.
    /// False means unknown, not unpasteable, so callers must not use it to veto
    /// a Command-V attempt.
    private static func focusedElementProvidesTextEvidence() -> Bool {
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

        var selectedTextIsSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextIsSettable
        ) == .success, selectedTextIsSettable.boolValue {
            return true
        }

        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success,
              let role = roleValue as? String,
              textRoles.contains(role) else {
            return false
        }

        // A text role alone can describe a read-only control. A writable value
        // is the positive evidence that makes clipboard restoration reasonable.
        var valueIsSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &valueIsSettable
        ) == .success && valueIsSettable.boolValue
    }
}
