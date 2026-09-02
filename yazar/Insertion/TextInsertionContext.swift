import Foundation

/// The target text surrounding the selection at dictation stop.
///
/// Accessibility ranges use UTF-16 offsets, so construction from a complete
/// value stays here rather than letting callers index Swift strings themselves.
nonisolated struct TextInsertionContext: Equatable, Sendable {
    let beforeText: String
    let selectedText: String
    let afterText: String
    let applicationBundleIdentifier: String?

    init(
        beforeText: String,
        selectedText: String,
        afterText: String,
        applicationBundleIdentifier: String? = nil
    ) {
        self.beforeText = beforeText
        self.selectedText = selectedText
        self.afterText = afterText
        self.applicationBundleIdentifier = applicationBundleIdentifier
    }

    init?(
        contents: String,
        selectedRange: NSRange,
        applicationBundleIdentifier: String? = nil
    ) {
        guard selectedRange.location >= 0,
              selectedRange.length >= 0 else { return nil }

        let (selectionEnd, overflowed) = selectedRange.location.addingReportingOverflow(
            selectedRange.length
        )
        let contents = contents as NSString
        guard !overflowed,
              selectionEnd <= contents.length,
              Self.isUTF16Boundary(selectedRange.location, in: contents),
              Self.isUTF16Boundary(selectionEnd, in: contents) else { return nil }

        beforeText = contents.substring(
            with: NSRange(location: 0, length: selectedRange.location)
        )
        selectedText = contents.substring(with: selectedRange)
        afterText = contents.substring(
            with: NSRange(
                location: selectionEnd,
                length: contents.length - selectionEnd
            )
        )
        self.applicationBundleIdentifier = applicationBundleIdentifier
    }

    /// `NSString` will manufacture an invalid string if a range cuts a UTF-16
    /// surrogate pair. Combining-sequence boundaries remain valid AX offsets.
    private static func isUTF16Boundary(_ offset: Int, in string: NSString) -> Bool {
        guard offset > 0, offset < string.length else { return true }
        let previous = string.character(at: offset - 1)
        let next = string.character(at: offset)
        let splitsSurrogatePair = (0xD800...0xDBFF).contains(previous)
            && (0xDC00...0xDFFF).contains(next)
        return !splitsSurrogatePair
    }
}
