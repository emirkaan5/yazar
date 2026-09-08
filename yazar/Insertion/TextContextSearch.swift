import ApplicationServices
import Foundation

/// Resolves one editor before reading text. Ordinary offsets never leave their
/// owning element; marker offsets are rebased against explicit editor bounds.
@MainActor
final class TextContextSearch {
    private let bundleIdentifier: String?
    private var visited: Set<AXUIElement> = []
    private(set) var editor: AXElement?
    private var hasMultipleSelections = false

    init(bundleIdentifier: String?) {
        self.bundleIdentifier = bundleIdentifier
    }

    func context(forFocused focused: AXElement) -> TextInsertionContext? {
        editor = findEditor(focused)
        guard let editor else {
            focused.session.note("No focused editor resolved")
            return nil
        }
        editor.session.note("Editor \(CFHash(editor.raw)), role \(editor.string(kAXRoleAttribute) ?? "unknown")")
        if let context = conventionalContext(editor) { return context }
        // Failed conventional messaging is not evidence that an inherited
        // marker is more authoritative. Retry the read first.
        guard !editor.session.needsRetry, !hasMultipleSelections else { return nil }
        return markerContext(editor, focused: focused)
    }

    private func findEditor(_ focused: AXElement) -> AXElement? {
        // The focused element's own state always outranks rendered fragments.
        if isEditor(focused) { return focused }
        var ancestor = focused.element(kAXParentAttribute)
        for _ in 0..<12 {
            guard let current = ancestor, visited.insert(current.raw).inserted else { break }
            if isEditor(current) { return current }
            if current.string(kAXRoleAttribute) == "AXWebArea" { break }
            ancestor = current.element(kAXParentAttribute)
        }
        // A generic focused container may contain the actual focus. Never
        // choose the first text-looking descendant or an unrelated static label.
        var pending = focused.elements(kAXChildrenAttribute)
        var index = 0
        while index < pending.count, index < 100, !focused.session.expired {
            let child = pending[index]
            index += 1
            guard visited.insert(child.raw).inserted else { continue }
            if child.number(kAXFocusedAttribute) == 1, isEditor(child) { return child }
            pending.append(contentsOf: child.elements(kAXChildrenAttribute))
        }
        return nil
    }

    private func isEditor(_ element: AXElement) -> Bool {
        let role = element.string(kAXRoleAttribute)
        if role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole {
            return element.string(kAXSubroleAttribute) != "AXSecureTextField"
        }
        return role == kAXGroupRole && element.number("AXEditable") == 1
    }

    private func conventionalContext(_ element: AXElement) -> TextInsertionContext? {
        guard let range = selectedRange(of: element) else { return nil }
        let selected = element.string(kAXSelectedTextAttribute)
        let value = element.string(kAXValueAttribute)
        let count = element.number(kAXNumberOfCharactersAttribute)
        if let value, count == nil || count == (value as NSString).length, let context = TextInsertionContext(
            contents: value, selectedRange: range, applicationBundleIdentifier: bundleIdentifier
        ), selected == nil || selected == context.selectedText {
            // Reread the selection to reject a caret moved during this attempt.
            guard selectedRange(of: element) == range else {
                element.session.retry("Selection changed during capture")
                return nil
            }
            element.session.note("Accepted editor AXValue and selection")
            return context
        }
        if let count, count >= 0,
           let contents = element.string(kAXStringForRangeParameterizedAttribute, for: NSRange(location: 0, length: count)),
           let context = TextInsertionContext(contents: contents, selectedRange: range,
                                              applicationBundleIdentifier: bundleIdentifier),
           selected == nil || selected == context.selectedText,
           selectedRange(of: element) == range {
            element.session.note("Accepted editor AXStringForRange and selection")
            return context
        }
        element.session.note("Conventional text/selection unavailable or inconsistent")
        return nil
    }

    private func selectedRange(of element: AXElement) -> NSRange? {
        let multiple = element.ranges(kAXSelectedTextRangesAttribute)
        guard multiple.count <= 1 else {
            hasMultipleSelections = true
            element.session.note("Multiple selections are unsupported")
            return nil
        }
        return element.range(kAXSelectedTextRangeAttribute) ?? multiple.first
    }

    private func markerContext(_ editor: AXElement, focused: AXElement) -> TextInsertionContext? {
        guard let bounds = editor.editorMarkerRange(),
              let selection = editor.textMarkerRange(kAXSelectedTextMarkerRangeAttribute)
                ?? focused.textMarkerRange(kAXSelectedTextMarkerRangeAttribute),
              let contents = editor.string(for: bounds) else { return nil }
        var translator: AXElement? = editor
        var translators: Set<AXUIElement> = []
        for _ in 0..<12 {
            guard let current = translator, translators.insert(current.raw).inserted else { break }
            // Both ranges use this translator's origin. The selected range is
            // then made relative to the editor, not to a parent document.
            if let editorRange = current.range(of: bounds),
               let selectedRange = current.range(of: selection),
               let context = TextInsertionContext(
                   contents: contents, editorRange: editorRange, selectedRange: selectedRange,
                   applicationBundleIdentifier: bundleIdentifier
               ), let selected = current.string(for: selection), selected == context.selectedText {
                editor.session.note("Accepted editor markers via \(CFHash(current.raw)); bounds \(editorRange), selection \(selectedRange)")
                return context
            }
            translator = current.element(kAXParentAttribute)
        }
        editor.session.note("Marker selection could not be placed inside editor bounds")
        return nil
    }
}
