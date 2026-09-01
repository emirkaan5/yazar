import AppKit
import ApplicationServices
import Foundation

/// Captures the target text surrounding the selection while dictation is active.
///
/// It owns only session timing: when to look, which application to watch, and
/// which snapshot survives. `TextContextSearch` owns how to read a textbox.
/// Unsupported Accessibility representations degrade to nil instead of blocking
/// paste.
@MainActor
final class TextContextCapture: NSObject {
    private static let manualAccessibilityAttribute = "AXManualAccessibility"
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    private let systemWideElement = AXUIElementCreateSystemWide()
    private var latestContext: TextInsertionContext?
    private var isCapturing = false
    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedProcessID: pid_t?
    private var accessibilityEnabledProcessIDs: Set<pid_t> = []

    /// Starts a fresh session and captures the currently focused target.
    func begin() {
        cancel()
        isCapturing = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        refresh()
        observeApplication(processID: focusedProcessID() ?? frontmostProcessID)
    }

    /// Refreshes at dictation stop and returns that newest result.
    func finish() -> TextInsertionContext? {
        guard isCapturing else { return nil }
        refresh()
        let context = latestContext
        endSession()
        return context
    }

    /// Ends an abandoned session without preserving its context.
    func cancel() {
        endSession()
    }

    private func endSession() {
        stopObserving()
        accessibilityEnabledProcessIDs.removeAll()
        latestContext = nil
        isCapturing = false
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        guard isCapturing else { return }
        refresh()
        let processID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication)?.processIdentifier
        observeApplication(processID: processID ?? focusedProcessID() ?? frontmostProcessID)
    }

    fileprivate func focusedElementChanged() {
        guard isCapturing else { return }
        refresh()
    }

    private func refresh() {
        latestContext = captureContext()
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

    private func focusedProcessID() -> pid_t? {
        systemWideElement.element(kAXFocusedUIElementAttribute)?.processID
    }

    private func observeApplication(processID: pid_t?) {
        guard observedProcessID != processID else { return }
        stopAXObservation()
        guard let processID else { return }

        let application = AXUIElementCreateApplication(processID)
        var observer: AXObserver?
        guard AXObserverCreate(
            processID,
            textContextFocusChangedCallback,
            &observer
        ) == .success,
              let observer,
              AXObserverAddNotification(
                observer,
                application,
                kAXFocusedUIElementChangedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
              ) == .success else { return }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        self.observer = observer
        observedApplication = application
        observedProcessID = processID
    }

    private func stopObserving() {
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        stopAXObservation()
    }

    private func stopAXObservation() {
        if let observer, let observedApplication {
            AXObserverRemoveNotification(
                observer,
                observedApplication,
                kAXFocusedUIElementChangedNotification as CFString
            )
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        observedApplication = nil
        observedProcessID = nil
    }
}

private nonisolated func textContextFocusChangedCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }
    let capture = Unmanaged<TextContextCapture>.fromOpaque(userInfo).takeUnretainedValue()
    MainActor.assumeIsolated {
        capture.focusedElementChanged()
    }
}
