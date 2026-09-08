import ApplicationServices
import Foundation

/// A capture result retains target identity independently of text availability.
/// Debug reports retain metadata and text, but never own a live AX read session.
@MainActor
struct TextInputSnapshot {
    let date = Date()
    var processID: pid_t?
    var applicationBundleIdentifier: String?
    var focusedElement: AXUIElement?
    var editor: AXUIElement?
    var context: TextInsertionContext?
    var status = "Context unavailable"
    var shouldRetry = false
    var attempts = 1
    var elapsedMilliseconds = 0
    var details: [String] = []

    /// Missing AX information is not proof of a focus change. Compare the
    /// strongest identity both captures actually obtained.
    func targetChanged(since previous: TextInputSnapshot) -> Bool {
        if let processID, let previousID = previous.processID, processID != previousID { return true }
        if let editor, let previousEditor = previous.editor { return !CFEqual(editor, previousEditor) }
        if let focusedElement, let previousFocus = previous.focusedElement {
            return !CFEqual(focusedElement, previousFocus)
        }
        return false
    }
}
