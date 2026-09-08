import AppKit
import ApplicationServices
import Foundation

/// Warms the target at recording start and refreshes context before delivery.
/// Every read attempt has its own deadline; retries yield so cancellation and
/// the target application's accessibility initialization can make progress.
@MainActor
final class TextContextCapture {
    private var isCapturing = false
    private var activationDetails: [String] = []

    func begin() {
        isCapturing = true
        let session = AXReadSession()
        if AXIsProcessTrusted(), let application = NSWorkspace.shared.frontmostApplication {
            _ = Self.enableAccessibilityTree(for: application.processIdentifier, session: session)
        }
        activationDetails = session.messages
    }

    func finish() -> TextInputSnapshot? {
        guard isCapturing else { return nil }
        defer { cancel() }
        var snapshot = Self.capture()
        snapshot.details = ["Recording-start activation"] + activationDetails + snapshot.details
        return snapshot
    }

    func cancel() {
        isCapturing = false
        activationDetails.removeAll()
    }

    /// The debug monitor uses this same path without modifying dictation state.
    static func refresh() async throws -> TextInputSnapshot {
        let start = ContinuousClock.now
        var details: [String] = []
        for attempt in 1...3 {
            try Task.checkCancellation()
            var snapshot = capture()
            details += ["Attempt \(attempt)"] + snapshot.details
            snapshot.attempts = attempt
            snapshot.details = details
            let elapsed = start.duration(to: .now)
            snapshot.elapsedMilliseconds = Int(elapsed.components.seconds * 1_000)
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            if !snapshot.shouldRetry || attempt == 3 { return snapshot }
            try await Task.sleep(for: .milliseconds(50))
        }
        preconditionFailure("The final attempt always returns")
    }

    private static func capture() -> TextInputSnapshot {
        let session = AXReadSession()
        let frontmost = NSWorkspace.shared.frontmostApplication
        var snapshot = TextInputSnapshot(
            processID: frontmost?.processIdentifier,
            applicationBundleIdentifier: frontmost?.bundleIdentifier
        )
        guard AXIsProcessTrusted() else {
            snapshot.status = "Accessibility permission unavailable"
            return snapshot
        }
        let activated = frontmost.map {
            enableAccessibilityTree(for: $0.processIdentifier, session: session)
        } ?? false
        let system = AXElement(raw: AXUIElementCreateSystemWide(), session: session)
        let application = frontmost.map {
            AXElement(raw: AXUIElementCreateApplication($0.processIdentifier), session: session)
        }
        guard let focused = application?.element(kAXFocusedUIElementAttribute)
                ?? system.element(kAXFocusedUIElementAttribute) else {
            snapshot.status = "Focused element unavailable"
            snapshot.shouldRetry = true
            snapshot.details = session.messages
            snapshot.elapsedMilliseconds = session.elapsedMilliseconds
            return snapshot
        }
        snapshot.focusedElement = focused.raw
        snapshot.processID = focused.processID ?? snapshot.processID
        snapshot.applicationBundleIdentifier = snapshot.processID.flatMap {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }
        let search = TextContextSearch(bundleIdentifier: snapshot.applicationBundleIdentifier)
        snapshot.context = search.context(forFocused: focused)
        snapshot.editor = search.editor?.raw
        let finalFocus = application?.element(kAXFocusedUIElementAttribute)
            ?? system.element(kAXFocusedUIElementAttribute)
        let sameFocus = finalFocus.map { CFEqual(focused.raw, $0.raw) } ?? false
        if !sameFocus {
            snapshot.context = nil
            session.note("Focus changed or became unavailable during capture")
        }
        snapshot.shouldRetry = snapshot.context == nil
            && (session.needsRetry || session.expired || activated || !sameFocus)
        snapshot.status = snapshot.context == nil ? "Context unavailable; use unfitted transcript" : "Context captured"
        snapshot.details = session.messages
        snapshot.elapsedMilliseconds = session.elapsedMilliseconds
        return snapshot
    }

    /// Never cache a failed activation as success. Unsupported applications
    /// reject these attributes; transient failures remain visible to the caller.
    private static func enableAccessibilityTree(for processID: pid_t, session: AXReadSession) -> Bool {
        let application = AXElement(raw: AXUIElementCreateApplication(processID), session: session)
        let manual = application.setAttribute("AXManualAccessibility", to: kCFBooleanTrue)
        let enhanced = application.setAttribute("AXEnhancedUserInterface", to: kCFBooleanTrue)
        return manual == .success || enhanced == .success
    }
}
