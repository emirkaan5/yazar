import ApplicationServices
import Foundation

/// One depth-first search of a focused element's accessibility tree for a
/// coherent textbox value and selection.
///
/// Targets expose equivalent text state through incompatible representations.
/// Native controls answer with a value and a character range. Web and Electron
/// editors answer with opaque text markers that often sit on a different node
/// than the one able to translate them, and that a container may inherit from
/// the whole document. The search therefore keeps the two coordinate spaces
/// apart, lets a direct text role answer with its own value before any marker
/// it inherited, and pairs contents with a selection only when one node is an
/// ancestor of the other.
///
/// It lives for exactly one traversal. `probes` is its scratch table, not
/// state that outlives the answer.
@MainActor
final class TextContextSearch {
    // Browser and Electron editors put the focused text node several generic
    // containers below the system-wide focused element, so the walk has to go
    // deep, and needs a bound rather than a depth guess.
    private static let maximumElementCount = 1_000
    private static let directTextRoles = Set([
        kAXStaticTextRole,
        kAXTextAreaRole,
        kAXTextFieldRole,
    ])
    private static let webAreaRole = "AXWebArea"

    private let bundleIdentifier: String?
    private var probes: [Probe] = []
    private var visited: Set<AXUIElement> = []

    init(bundleIdentifier: String?) {
        self.bundleIdentifier = bundleIdentifier
    }

    /// Searches the focused subtree, then the focused element's containers.
    /// Returns nil when no pairing produces a valid UTF-16 range, which leaves
    /// the transcript unfitted rather than fitted to the wrong text.
    func context(forFocused element: AXUIElement) -> TextInsertionContext? {
        guard let index = addProbe(
            for: element,
            parentIndex: nil,
            isInFocusedSubtree: true
        ) else { return nil }

        let children = childrenToSearch(of: element, role: probes[index].role)
        for child in children ?? [] {
            if let context = search(child, parentIndex: index) { return context }
        }
        if let context = context(at: index) { return context }

        // A focused direct text role is already the textbox. Its containers
        // cannot improve on it, and their document-wide markers are not this
        // field's selection.
        guard children != nil else { return nil }
        return searchAncestors(of: element, from: index)
    }

    private func search(
        _ element: AXUIElement,
        parentIndex: Int
    ) -> TextInsertionContext? {
        guard let index = addProbe(
            for: element,
            parentIndex: parentIndex,
            isInFocusedSubtree: true
        ) else { return nil }

        for child in childrenToSearch(of: element, role: probes[index].role) ?? [] {
            if let context = search(child, parentIndex: index) { return context }
        }
        return context(at: index)
    }

    /// Follows the focused element's containers upward. Their other children
    /// stay out of the walk: a checkbox that inherited a page-level marker is
    /// not the focused textbox.
    private func searchAncestors(
        of element: AXUIElement,
        from childIndex: Int
    ) -> TextInsertionContext? {
        var element = element
        var childIndex = childIndex

        while let parent = element.element(kAXParentAttribute) {
            guard let index = addProbe(
                for: parent,
                parentIndex: nil,
                isInFocusedSubtree: false
            ) else { return nil }
            // The walk knows this link, so ancestry never costs an AXParent read.
            probes[childIndex].parentIndex = index

            if let context = context(at: index) { return context }
            // Same rule as the subtree leaves: a container that is itself a text
            // control ends the walk, because nothing above it is the textbox.
            guard !probes[index].isDirectText else { return nil }

            element = parent
            childIndex = index
        }
        return nil
    }

    /// Nodes that are themselves a text control answer alone; descending finds
    /// only their own rendered fragments. Returns nil for those, and otherwise
    /// the children to search in AX's own order.
    private func childrenToSearch(
        of element: AXUIElement,
        role: String?
    ) -> [AXUIElement]? {
        if role == kAXStaticTextRole || role == kAXTextFieldRole { return nil }
        let children = element.elements(kAXVisibleChildrenAttribute)
            + element.elements(kAXChildrenAttribute)
        if role == kAXTextAreaRole, children.isEmpty { return nil }
        return children
    }

    /// Tries the probe on its own, then paired with every relative already
    /// probed. Contents and selection may sit on different nodes, but only
    /// along one root-to-leaf path.
    private func context(at index: Int) -> TextInsertionContext? {
        let probe = probes[index]
        if let context = context(contents: probe, selection: probe) { return context }

        for other in probes.indices where other != index {
            guard isAncestor(other, of: index) || isAncestor(index, of: other)
            else { continue }
            if let context = context(contents: probe, selection: probes[other])
                ?? context(contents: probes[other], selection: probe) {
                return context
            }
        }
        return nil
    }

    private func isAncestor(_ ancestor: Int, of descendant: Int) -> Bool {
        var current = probes[descendant].parentIndex
        // The walk builds a forest, so this cannot loop; the bound only keeps a
        // malformed tree from hanging the dictation.
        for _ in probes.indices {
            guard let index = current else { return false }
            if index == ancestor { return true }
            current = probes[index].parentIndex
        }
        return false
    }

    /// Tries one node's contents against another's selection, conventional
    /// representation first. Electron inherits a document-wide marker onto a
    /// field-local text area that also exposes the correct value and range, so
    /// preferring markers here would pick the larger but wrong text.
    private func context(
        contents contentsProbe: Probe,
        selection selectionProbe: Probe
    ) -> TextInsertionContext? {
        for contents in contentsProbe.conventionalContents {
            // An empty value is real text only for a control that owns text.
            guard !contents.isEmpty || contentsProbe.isDirectText else { continue }
            if let context = context(
                contents: contents,
                selectedRanges: selectionProbe.selectedRanges,
                selectedTexts: selectionProbe.selectedTexts
            ) {
                return context
            }
        }

        guard let contents = contentsProbe.markerContents,
              let markerRange = selectionProbe.selectedMarkerRange else { return nil }

        // Web editors often expose the marker on a child but convert it only on
        // an ancestor, so ask both ends of the pair.
        var ranges: [NSRange] = []
        for element in [contentsProbe.element, selectionProbe.element] {
            if let range = element.range(of: markerRange) { append(range, to: &ranges) }
        }
        var selectedTexts = selectionProbe.selectedTexts
        if let selectedText = contentsProbe.element.string(for: markerRange),
           !selectedTexts.contains(selectedText) {
            selectedTexts.append(selectedText)
        }
        return context(
            contents: contents,
            selectedRanges: ranges,
            selectedTexts: selectedTexts
        )
    }

    /// Accepts the first range that splits `contents` validly and agrees with
    /// any selected string the target reported.
    private func context(
        contents: String,
        selectedRanges: [NSRange],
        selectedTexts: [String]
    ) -> TextInsertionContext? {
        for selectedRange in selectedRanges {
            guard let context = TextInsertionContext(
                contents: contents,
                selectedRange: selectedRange,
                applicationBundleIdentifier: bundleIdentifier
            ) else { continue }
            if selectedTexts.isEmpty || selectedTexts.contains(context.selectedText) {
                return context
            }
        }

        for selectedText in selectedTexts where !selectedText.isEmpty {
            if let context = context(byFinding: selectedText, in: contents) {
                return context
            }
        }
        return nil
    }

    /// Some nested web nodes expose the selected string but report a range in a
    /// child's coordinate space. Use it only when the selection occurs once in
    /// the content; otherwise guessing could rewrite the wrong occurrence.
    private func context(
        byFinding selectedText: String,
        in contents: String
    ) -> TextInsertionContext? {
        guard !selectedText.isEmpty else { return nil }
        let contents = contents as NSString
        let firstRange = contents.range(of: selectedText)
        guard firstRange.location != NSNotFound else { return nil }
        let remainingLocation = firstRange.location + firstRange.length
        let remainingRange = NSRange(
            location: remainingLocation,
            length: contents.length - remainingLocation
        )
        guard contents.range(of: selectedText, range: remainingRange).location == NSNotFound
        else { return nil }
        return TextInsertionContext(
            contents: contents as String,
            selectedRange: firstRange,
            applicationBundleIdentifier: bundleIdentifier
        )
    }

    // MARK: - Probing

    private func addProbe(
        for element: AXUIElement,
        parentIndex: Int?,
        isInFocusedSubtree: Bool
    ) -> Int? {
        guard probes.count < Self.maximumElementCount,
              visited.insert(element).inserted else { return nil }

        let role = element.string(kAXRoleAttribute)
        // Marker reads are the expensive attributes, and only these roles may
        // speak for the textbox through one. Gating the read instead of the
        // result keeps unrelated nodes off the wire entirely.
        let readsMarkers = Self.usesTextMarkers(role)
        let selectedMarkerRange = readsMarkers && isInFocusedSubtree
            ? element.textMarkerRange(kAXSelectedTextMarkerRangeAttribute)
            : nil

        probes.append(
            Probe(
                element: element,
                role: role,
                parentIndex: parentIndex,
                conventionalContents: conventionalContents(of: element),
                markerContents: readsMarkers ? markerContents(of: element) : nil,
                selectedTexts: selectedTexts(of: element, markerRange: selectedMarkerRange),
                selectedRanges: selectedRanges(of: element),
                selectedMarkerRange: selectedMarkerRange
            )
        )
        return probes.endIndex - 1
    }

    /// A selection marker may come only from a text, group, or web-area node
    /// inside the focused subtree. Contents may also come from a container
    /// above it, because the web area holding the document text is often the
    /// focused editor's ancestor.
    private static func usesTextMarkers(_ role: String?) -> Bool {
        guard let role else { return false }
        return directTextRoles.contains(role) || role == webAreaRole || role == kAXGroupRole
    }

    /// Longest first: an empty `AXValue` must not hide nonempty text that the
    /// same element will hand over one character range at a time.
    private func conventionalContents(of element: AXUIElement) -> [String] {
        var candidates: [String] = []
        if let contents = element.string(kAXValueAttribute) {
            candidates.append(contents)
        }
        if let characterCount = element.number(kAXNumberOfCharactersAttribute),
           characterCount >= 0,
           let contents = element.string(
               kAXStringForRangeParameterizedAttribute,
               for: NSRange(location: 0, length: characterCount)
           ), !candidates.contains(contents) {
            candidates.append(contents)
        }
        return candidates.sorted { ($0 as NSString).length > ($1 as NSString).length }
    }

    private func markerContents(of element: AXUIElement) -> String? {
        guard let start = element.textMarker(kAXStartTextMarkerAttribute),
              let end = element.textMarker(kAXEndTextMarkerAttribute) else { return nil }
        return element.string(for: AXTextMarkerRangeCreate(nil, start, end))
    }

    private func selectedTexts(
        of element: AXUIElement,
        markerRange: AXTextMarkerRange?
    ) -> [String] {
        var candidates: [String] = []
        if let selectedText = element.string(kAXSelectedTextAttribute) {
            candidates.append(selectedText)
        }
        if let markerRange,
           let selectedText = element.string(for: markerRange),
           !candidates.contains(selectedText) {
            candidates.append(selectedText)
        }
        return candidates
    }

    private func selectedRanges(of element: AXUIElement) -> [NSRange] {
        var ranges: [NSRange] = []
        for attribute in [
            kAXSelectedTextRangeAttribute,
            kAXSharedCharacterRangeAttribute,
        ] {
            if let range = element.range(attribute) { append(range, to: &ranges) }
        }
        for range in element.ranges(kAXSelectedTextRangesAttribute) {
            append(range, to: &ranges)
        }
        return ranges
    }

    private func append(_ range: NSRange, to ranges: inout [NSRange]) {
        guard !ranges.contains(range) else { return }
        ranges.append(range)
    }

    /// One element's text state, read once. Every field costs a cross-process
    /// call, and the pairing loop revisits each element many times.
    private struct Probe {
        let element: AXUIElement
        let role: String?
        /// Assigned by the walk. The ancestor phase back-patches the node it
        /// came from, so ancestry is never re-derived from AX.
        var parentIndex: Int?
        let conventionalContents: [String]
        let markerContents: String?
        let selectedTexts: [String]
        let selectedRanges: [NSRange]
        let selectedMarkerRange: AXTextMarkerRange?

        var isDirectText: Bool {
            role.map(TextContextSearch.directTextRoles.contains) ?? false
        }
    }
}
