import ApplicationServices
import Foundation

/// One bounded AX attempt. Error provenance survives typed optional reads so a
/// temporarily unresponsive process can be retried without retrying unsupported APIs.
@MainActor
final class AXReadSession {
    let deadline: ContinuousClock.Instant
    private(set) var needsRetry = false
    private(set) var expired = false
    private(set) var messages: [String] = []

    init(budget: Duration = .milliseconds(180)) {
        deadline = .now + budget
    }

    func prepare(_ element: AXUIElement) -> Bool {
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else {
            if !expired { note("AX attempt deadline exceeded") }
            expired = true
            return false
        }
        let seconds = Double(remaining.components.seconds)
            + Double(remaining.components.attoseconds) / 1e18
        AXUIElementSetMessagingTimeout(element, Float(min(seconds, 0.05)))
        return true
    }

    func record(_ element: AXUIElement, attribute: String, error: AXError, value: CFTypeRef?) {
        if error == .cannotComplete || error == .invalidUIElement { needsRetry = true }
#if DEBUG
        note("\(CFHash(element)) \(attribute): \(error) (\(error.rawValue))\(value.map { " → " + summary($0) } ?? "")")
#endif
    }

    func note(_ message: String) {
#if DEBUG
        if messages.count < 250 { messages.append(message) }
        else if messages.count == 250 { messages.append("Further AX details omitted (250-entry limit)") }
#endif
    }

    private func summary(_ value: CFTypeRef) -> String {
        if let text = value as? String { return "string, \((text as NSString).length) UTF-16 units" }
        if let text = value as? NSAttributedString { return "attributed string, \(text.length) UTF-16 units" }
        if CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = unsafeDowncast(value, to: AXValue.self)
            if AXValueGetType(axValue) == .cfRange {
                var range = CFRange()
                if AXValueGetValue(axValue, .cfRange, &range) { return "range \(range.location):\(range.length)" }
            }
        }
        if let number = value as? NSNumber { return number.stringValue }
        if let array = value as? [Any] { return "array, \(array.count) entries" }
        return "CF type \(CFGetTypeID(value))"
    }
}
