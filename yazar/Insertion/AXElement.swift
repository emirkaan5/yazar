import ApplicationServices
import Foundation

/// Typed reads over the C Accessibility boundary. Related elements carry the
/// same attempt budget and diagnostics; optional values do not erase AX errors.
@MainActor
struct AXElement {
    let raw: AXUIElement
    let session: AXReadSession

    var processID: pid_t? {
        var processID = pid_t()
        guard AXUIElementGetPid(raw, &processID) == .success else { return nil }
        return processID
    }

    func attribute(_ name: String) -> CFTypeRef? {
        guard session.prepare(raw) else { return nil }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(raw, name as CFString, &value)
        session.record(raw, attribute: name, error: error, value: value)
        return error == .success ? value : nil
    }

    func parameterizedAttribute(_ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        guard session.prepare(raw) else { return nil }
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(raw, name as CFString, parameter, &value)
        session.record(raw, attribute: name, error: error, value: value)
        return error == .success ? value : nil
    }

    @discardableResult
    func setAttribute(_ name: String, to value: CFTypeRef) -> AXError {
        guard session.prepare(raw) else { return .cannotComplete }
        let error = AXUIElementSetAttributeValue(raw, name as CFString, value)
        session.record(raw, attribute: "set " + name, error: error, value: nil)
        return error
    }

    func element(_ name: String) -> AXElement? {
        attribute(name).flatMap(Self.element(from:)).map { AXElement(raw: $0, session: session) }
    }

    func elements(_ name: String) -> [AXElement] {
        guard let values = attribute(name) as? [Any] else { return [] }
        return values.compactMap { Self.element(from: $0 as CFTypeRef) }
            .map { AXElement(raw: $0, session: session) }
    }

    /// AX answers with `String` or `NSAttributedString` depending on the
    /// attribute and the target; both carry the same text to a caller.
    func string(_ name: String) -> String? {
        Self.string(from: attribute(name))
    }

    func number(_ name: String) -> Int? {
        (attribute(name) as? NSNumber)?.intValue
    }

    func range(_ name: String) -> NSRange? {
        attribute(name).flatMap(Self.range(from:))
    }

    /// `AXSelectedTextRanges` answers with an array of range values.
    func ranges(_ name: String) -> [NSRange] {
        guard let values = attribute(name) as? [Any] else { return [] }
        return values.compactMap { Self.range(from: $0 as CFTypeRef) }
    }

    func string(_ name: String, for range: NSRange) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        return Self.string(from: parameterizedAttribute(name, parameter))
    }

    // MARK: - Text markers

    // Web and Electron editors describe position with opaque markers instead of
    // character offsets. Decoding them stays here; which element may speak for
    // the focused textbox through a marker is a caller's decision.

    func textMarkerRange(_ name: String) -> AXTextMarkerRange? {
        guard let value = attribute(name),
              CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXTextMarkerRange.self)
    }

    func string(for markerRange: AXTextMarkerRange) -> String? {
        Self.string(from: parameterizedAttribute(
            kAXAttributedStringForTextMarkerRangeParameterizedAttribute,
            markerRange
        ))
    }

    /// The range belonging to this editor, never the inherited document bounds.
    func markerRange(for editor: AXElement) -> AXTextMarkerRange? {
        guard let value = parameterizedAttribute("AXTextMarkerRangeForUIElement", editor.raw),
              CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXTextMarkerRange.self)
    }

    /// Both editor bounds and selection must be converted by the same element.
    func range(of markerRange: AXTextMarkerRange) -> NSRange? {
        guard let start = index(of: AXTextMarkerRangeCopyStartMarker(markerRange)),
              let end = index(of: AXTextMarkerRangeCopyEndMarker(markerRange)),
              start >= 0,
              end >= 0 else { return nil }
        return NSRange(location: min(start, end), length: abs(end - start))
    }

    private func index(of marker: AXTextMarker) -> Int? {
        (parameterizedAttribute(
            kAXIndexForTextMarkerParameterizedAttribute,
            marker
        ) as? NSNumber)?.intValue
    }

    private static func element(from value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(from value: CFTypeRef?) -> String? {
        if let string = value as? String { return string }
        return (value as? NSAttributedString)?.string
    }

    private static func range(from value: CFTypeRef) -> NSRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
