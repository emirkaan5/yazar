import AppKit
import ApplicationServices
import Foundation

/// Captures the target text surrounding the selection at dictation stop.
///
/// It owns only session timing: opting the target application's accessibility
/// tree in when dictation starts, and reading the focused textbox when it ends.
/// `TextContextSearch` owns how to read a textbox. Unsupported Accessibility
/// representations degrade to nil instead of blocking paste.
@MainActor
final class TextContextCapture {
    private static let manualAccessibilityAttribute = "AXManualAccessibility"
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    private let systemWideElement = AXUIElementCreateSystemWide()
    private var isCapturing = false
    private var accessibilityEnabledProcessIDs: Set<pid_t> = []

    /// Starts a session. Only the opt-in happens here: Chromium and Electron
    /// build their trees in response to it, so asking at dictation start gives
    /// them the hold duration to answer rather than one runloop turn.
    func begin() {
        cancel()
        isCapturing = true
        if let processID = frontmostProcessID {
            enableAccessibilityTree(for: processID)
        }
    }

    /// Captures the focused target at recording stop. Only this snapshot
    /// reaches the fitter; focus during the hold does not matter, because the
    /// text Yazar formats against is the text it is about to paste into.
    func finish() -> TextInsertionContext? {
        guard isCapturing else { return nil }
        defer { endSession() }
        return captureContext()
    }

    /// Ends an abandoned session.
    func cancel() {
        endSession()
    }

    private func endSession() {
        accessibilityEnabledProcessIDs.removeAll()
        isCapturing = false
    }

    private func captureContext() -> TextInsertionContext? {
        guard AXIsProcessTrusted() else { return nil }

        // Chromium may not publish a useful focused element until a trusted
        // client explicitly enables the frontmost application's AX tree.
        let initialFrontmostProcessID = frontmostProcessID
        if let initialFrontmostProcessID {
            enableAccessibilityTree(for: initialFrontmostProcessID)
        }

        guard let element = systemWideElement.element(kAXFocusedUIElementAttribute),
              let processID = element.processID else { return nil }
        if processID != initialFrontmostProcessID {
            enableAccessibilityTree(for: processID)
        }
        // Opting the application in can replace the focused element with the
        // real one, so read it again before walking anything.
        let focusedElement = systemWideElement
            .element(kAXFocusedUIElementAttribute) ?? element

        let search = TextContextSearch(
            bundleIdentifier: NSRunningApplication(
                processIdentifier: processID
            )?.bundleIdentifier
        )
        return search.context(forFocused: focusedElement).map(correctingNotesBoundary)
    }

    /// Notes reports a caret at the start of a line as sitting after the
    /// previous line's newline, which would make the fitter continue the wrong
    /// line. Move that newline to the far side of the caret.
    private func correctingNotesBoundary(
        in context: TextInsertionContext
    ) -> TextInsertionContext {
        guard context.applicationBundleIdentifier == "com.apple.notes",
              context.selectedText.isEmpty,
              !context.afterText.isEmpty,
              context.beforeText.last == "\n" else { return context }

        return TextInsertionContext(
            beforeText: String(context.beforeText.dropLast()),
            selectedText: context.selectedText,
            afterText: "\n" + context.afterText,
            applicationBundleIdentifier: context.applicationBundleIdentifier
        )
    }

    /// Chromium and Electron can keep their full accessibility trees dormant
    /// until a trusted client opts in. Unsupported applications reject both
    /// attributes without changing capture behavior. Once per process per
    /// session is enough; a dictation lasts seconds.
    private func enableAccessibilityTree(for processID: pid_t) {
        guard accessibilityEnabledProcessIDs.insert(processID).inserted else { return }
        let application = AXUIElementCreateApplication(processID)
        for attribute in [
            Self.manualAccessibilityAttribute,
            Self.enhancedUserInterfaceAttribute,
        ] {
            application.setAttribute(attribute, to: kCFBooleanTrue)
        }
    }

    private var frontmostProcessID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}
