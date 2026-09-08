#if DEBUG
import ApplicationServices
import Foundation

extension TextInputSnapshot {
    /// Escaping makes spaces, newlines and empty selections distinguishable.
    /// Only previews are truncated; the diagnostic explicitly reports the limit.
    var debugReport: String {
        let header = """
        \(date.ISO8601Format()) — \(status)
        App: \(applicationBundleIdentifier ?? "unknown") / PID: \(processID.map(String.init) ?? "unknown")
        Focus: \(focusedElement.map { String(CFHash($0)) } ?? "unavailable")
        Editor: \(editor.map { String(CFHash($0)) } ?? "unavailable")
        Attempts: \(attempts) / elapsed: \(elapsedMilliseconds) ms / retryable: \(shouldRetry)
        """
        var sections = [header]
        if let context {
            for (name, text) in [("Before", context.beforeText), ("Selected", context.selectedText), ("After", context.afterText)] {
                let preview = name == "Before" ? String(text.suffix(4_000)) : String(text.prefix(4_000))
                sections.append("\(name) (\((text as NSString).length) UTF-16 units): \(preview.debugDescription)"
                    + (preview != text ? " [preview limited to 4,000 characters]" : ""))
            }
        } else {
            sections.append("No fitting context accepted")
        }
        sections.append("AX READS\n" + details.joined(separator: "\n"))
        return sections.joined(separator: "\n\n")
    }
}
#endif
