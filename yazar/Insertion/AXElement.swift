import ApplicationServices
import Foundation

/// Typed, failure-tolerant reads over the C Accessibility API.
///
/// Every accessor returns nil, or an empty array, when the attribute is
/// missing, unsupported, or arrives as an unexpected Core Foundation type.
/// Callers treat all three the same way: this element cannot answer, ask
/// another one. Deciding which element to trust belongs to the caller; this
/// extension only knows how to get a Swift value out of one safely.
extension AXUIElement {
    var processID: pid_t? {
        var processID = pid_t()
        guard AXUIElementGetPid(self, &processID) == .success else { return nil }
        return processID
    }

    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success
        else { return nil }
        return value
    }

    func parameterizedAttribute(_ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            self,
            name as CFString,
            parameter,
            &value
        ) == .success else { return nil }
        return value
    }

    /// Applications that reject the attribute are the expected case, so the
    /// result is discarded rather than reported.
    func setAttribute(_ name: String, to value: CFTypeRef) {
        AXUIElementSetAttributeValue(self, name as CFString, value)
    }

    func element(_ name: String) -> AXUIElement? {
        attribute(name).flatMap(Self.element(from:))
    }

    func elements(_ name: String) -> [AXUIElement] {
        guard let values = attribute(name) as? [Any] else { return [] }
        return values.compactMap { Self.element(from: $0 as CFTypeRef) }
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

    func textMarker(_ name: String) -> AXTextMarker? {
        guard let value = attribute(name),
              CFGetTypeID(value) == AXTextMarkerGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXTextMarker.self)
    }

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

    /// Translates a marker range into this element's UTF-16 coordinate space.
    /// A marker exposed on a child often converts only on a web-area ancestor,
    /// so callers ask more than one element and keep whichever answers.
    func range(of markerRange: AXTextMarkerRange) -> NSRange? {
        guard let start = index(of: AXTextMarkerRangeCopyStartMarker(markerRange)),
              let end = index(of: AXTextMarkerRangeCopyEndMarker(markerRange)),
              start >= 0,
              end >= start else { return nil }
        return NSRange(location: start, length: end - start)
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
