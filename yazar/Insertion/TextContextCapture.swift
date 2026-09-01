import AppKit
import ApplicationServices
import Foundation

/// Captures the target text surrounding the selection while dictation is active.
/// Unsupported Accessibility representations degrade to nil instead of blocking paste.
@MainActor
final class TextContextCapture: NSObject {
    // Browser and Electron editors often put the focused text node several
    // generic accessibility containers below the system-wide focused element.
    private static let maximumElementCount = 1_000
    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface" as CFString
    private static let directTextRoles = Set([
        kAXStaticTextRole,
        kAXTextAreaRole,
        kAXTextFieldRole,
    ])
    private static let webAreaRole = "AXWebArea"

    private let systemWideElement = AXUIElementCreateSystemWide()
    private var latestContext: TextInsertionContext?
    private var isCapturing = false
    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedProcessID: pid_t?

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
        stopObserving()
        latestContext = nil
        isCapturing = false
        return context
    }

    /// Ends an abandoned session without preserving its context.
    func cancel() {
        stopObserving()
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
        if let frontmostProcessID = initialFrontmostProcessID {
            enableAccessibilityTree(for: frontmostProcessID)
        }

        guard var focusedElement = copiedElement(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWideElement
        ) else { return nil }

        var processID = pid_t()
        guard AXUIElementGetPid(focusedElement, &processID) == .success else { return nil }
        if processID != initialFrontmostProcessID {
            enableAccessibilityTree(for: processID)
        }
        if let refreshedElement = copiedElement(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWideElement
        ) {
            focusedElement = refreshedElement
        }
        let bundleIdentifier = NSRunningApplication(
            processIdentifier: processID
        )?.bundleIdentifier

        var probes: [ElementProbe] = []
        var pending: [TraversalStep] = [
            .visit(
                focusedElement,
                exploresChildren: true,
                exploresParent: true,
                isInFocusedSubtree: true
            ),
        ]
        var visited: Set<AXUIElement> = []

        while let step = pending.popLast() {
            switch step {
            case let .evaluate(probeIndex):
                let probe = probes[probeIndex]
                if let context = conventionalContext(
                    contentsProbe: probe,
                    selectionProbe: probe,
                    bundleIdentifier: bundleIdentifier
                ) {
                    return correctingNotesBoundary(in: context)
                }
                for otherProbe in probes.indices where otherProbe != probeIndex {
                    let other = probes[otherProbe]
                    guard sharesAncestry(probe, other, among: probes) else { continue }
                    if let context = conventionalContext(
                        contentsProbe: probe,
                        selectionProbe: other,
                        bundleIdentifier: bundleIdentifier
                    ) ?? conventionalContext(
                        contentsProbe: other,
                        selectionProbe: probe,
                        bundleIdentifier: bundleIdentifier
                    ) {
                        return correctingNotesBoundary(in: context)
                    }
                }

            case let .visit(
                element,
                exploresChildren,
                exploresParent,
                isInFocusedSubtree
            ):
                guard probes.count < Self.maximumElementCount else { continue }
                guard visited.insert(element).inserted else { continue }
                let probeIndex = probes.endIndex
                let probe = makeProbe(
                    for: element,
                    isInFocusedSubtree: isInFocusedSubtree
                )
                probes.append(probe)

                let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
                let visibleChildren = copiedElements(
                    kAXVisibleChildrenAttribute as CFString,
                    from: element
                ) ?? []
                let children = exploresChildren
                    ? visibleChildren + (
                        copiedElements(kAXChildrenAttribute as CFString, from: element) ?? []
                    )
                    : []
                let evaluatesBeforeChildren = role == kAXStaticTextRole
                    || role == kAXTextFieldRole
                    || (role == kAXTextAreaRole && children.isEmpty)

                if evaluatesBeforeChildren {
                    pending.append(.evaluate(probeIndex))
                    continue
                }

                if exploresParent,
                   let parent = copiedElement(
                    kAXParentAttribute as CFString,
                    from: element
                ) {
                    pending.append(
                        .visit(
                            parent,
                            exploresChildren: false,
                            exploresParent: true,
                            isInFocusedSubtree: false
                        )
                    )
                }
                pending.append(.evaluate(probeIndex))
                for child in children.reversed() {
                    pending.append(
                        .visit(
                            child,
                            exploresChildren: true,
                            exploresParent: false,
                            isInFocusedSubtree: true
                        )
                    )
                }
            }
        }

        return nil
    }

    private func sharesAncestry(
        _ first: ElementProbe,
        _ second: ElementProbe,
        among probes: [ElementProbe]
    ) -> Bool {
        isAncestor(first.identity, of: second, among: probes)
            || isAncestor(second.identity, of: first, among: probes)
    }

    private func isAncestor(
        _ possibleAncestor: AXUIElement,
        of descendant: ElementProbe,
        among probes: [ElementProbe]
    ) -> Bool {
        var parentIdentity = descendant.parentIdentity
        var visited: Set<AXUIElement> = []
        while let currentIdentity = parentIdentity,
              visited.insert(currentIdentity).inserted {
            if currentIdentity == possibleAncestor { return true }
            parentIdentity = probes.first {
                $0.identity == currentIdentity
            }?.parentIdentity
        }
        return false
    }

    private func conventionalContext(
        contentsProbe: ElementProbe,
        selectionProbe: ElementProbe,
        bundleIdentifier: String?
    ) -> TextInsertionContext? {
        for contents in contentsProbe.conventionalContents {
            guard !contents.isEmpty || contentsProbe.isDirectText else { continue }
            if let context = context(
                contents: contents,
                selectedRanges: selectionProbe.selectedRanges,
                selectedTexts: selectionProbe.selectedTexts,
                bundleIdentifier: bundleIdentifier
            ) {
                return context
            }
        }

        if selectionProbe.supportsMarkerSelection,
           let contents = contentsProbe.markerContents,
           let markerRange = selectionProbe.selectedMarkerRange {
            var ranges: [NSRange] = []
            var selectedTexts = selectionProbe.selectedTexts
            if let range = nsRange(from: markerRange, in: contentsProbe.identity) {
                append(range, to: &ranges)
            }
            if let range = nsRange(from: markerRange, in: selectionProbe.identity) {
                append(range, to: &ranges)
            }
            if let selectedText = text(
                for: markerRange,
                in: contentsProbe.identity
            ), !selectedTexts.contains(selectedText) {
                selectedTexts.append(selectedText)
            }
            if let context = context(
                contents: contents,
                selectedRanges: ranges,
                selectedTexts: selectedTexts,
                bundleIdentifier: bundleIdentifier
            ) {
                return context
            }
        }
        return nil
    }

    private func context(
        contents: String,
        selectedRanges: [NSRange],
        selectedTexts: [String],
        bundleIdentifier: String?
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
            if let context = contextByFinding(
                selectedText,
                in: contents,
                bundleIdentifier: bundleIdentifier
            ) {
                return context
            }
        }
        return nil
    }

    /// Some nested web nodes expose the selected string but report a range in a
    /// child's coordinate space. Use it only when the selection occurs once in
    /// the content; otherwise guessing could rewrite the wrong occurrence.
    private func contextByFinding(
        _ selectedText: String,
        in contents: String,
        bundleIdentifier: String?
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

    private func correctingNotesBoundary(
        in context: TextInsertionContext
    ) -> TextInsertionContext {
        guard context.applicationBundleIdentifier == "com.apple.notes",
              context.selectedText.isEmpty,
              !context.afterText.isEmpty,
              context.beforeText.last == "\n" else { return context }

        var beforeText = context.beforeText
        beforeText.removeLast()
        return TextInsertionContext(
            beforeText: beforeText,
            selectedText: context.selectedText,
            afterText: "\n" + context.afterText,
            applicationBundleIdentifier: context.applicationBundleIdentifier
        )
    }

    private func makeProbe(
        for element: AXUIElement,
        isInFocusedSubtree: Bool
    ) -> ElementProbe {
        let selectedMarkerRange = selectedTextMarkerRange(from: element)
        return ElementProbe(
            identity: element,
            parentIdentity: copiedElement(
                kAXParentAttribute as CFString,
                from: element
            ),
            role: stringAttribute(kAXRoleAttribute as CFString, from: element),
            isInFocusedSubtree: isInFocusedSubtree,
            conventionalContents: conventionalContents(from: element),
            markerContents: textMarkerContents(from: element),
            selectedTexts: selectedTexts(
                from: element,
                markerRange: selectedMarkerRange
            ),
            selectedRanges: selectedRanges(from: element),
            selectedMarkerRange: selectedMarkerRange
        )
    }

    private func conventionalContents(from element: AXUIElement) -> [String] {
        var candidates: [String] = []
        if let contents = stringAttribute(kAXValueAttribute as CFString, from: element) {
            candidates.append(contents)
        }
        if let characterCount = numberAttribute(
            kAXNumberOfCharactersAttribute as CFString,
            from: element
        ), characterCount >= 0,
           let contents = string(
            for: NSRange(location: 0, length: characterCount),
            in: element
           ), !candidates.contains(contents) {
            candidates.append(contents)
        }
        return candidates.sorted {
            ($0 as NSString).length > ($1 as NSString).length
        }
    }

    private func textMarkerContents(from element: AXUIElement) -> String? {
        guard let startValue = copiedAttribute(
            kAXStartTextMarkerAttribute as CFString,
            from: element
        ), CFGetTypeID(startValue) == AXTextMarkerGetTypeID(),
              let endValue = copiedAttribute(
                kAXEndTextMarkerAttribute as CFString,
                from: element
              ), CFGetTypeID(endValue) == AXTextMarkerGetTypeID() else { return nil }
        let range = AXTextMarkerRangeCreate(
            nil,
            unsafeDowncast(startValue, to: AXTextMarker.self),
            unsafeDowncast(endValue, to: AXTextMarker.self)
        )
        return text(for: range, in: element)
    }

    private func selectedTexts(
        from element: AXUIElement,
        markerRange: AXTextMarkerRange?
    ) -> [String] {
        var candidates: [String] = []
        if let selectedText = stringAttribute(
            kAXSelectedTextAttribute as CFString,
            from: element
        ) {
            candidates.append(selectedText)
        }
        if let markerRange,
           let selectedText = text(for: markerRange, in: element) {
            if !candidates.contains(selectedText) {
                candidates.append(selectedText)
            }
        }
        return candidates
    }

    private func text(
        for markerRange: AXTextMarkerRange,
        in element: AXUIElement
    ) -> String? {
        guard let value = copiedParameterizedAttribute(
            kAXAttributedStringForTextMarkerRangeParameterizedAttribute as CFString,
            parameter: markerRange,
            from: element
        ) else { return nil }
        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }
        return value as? String
    }

    private func selectedRanges(from element: AXUIElement) -> [NSRange] {
        var ranges: [NSRange] = []
        for attribute in [
            kAXSelectedTextRangeAttribute as CFString,
            kAXSharedCharacterRangeAttribute as CFString,
        ] {
            if let value = copiedAttribute(attribute, from: element),
               let range = cfRange(from: value) {
                append(
                    NSRange(location: range.location, length: range.length),
                    to: &ranges
                )
            }
        }

        if let value = copiedAttribute(
            kAXSelectedTextRangesAttribute as CFString,
            from: element
        ), let values = value as? [Any] {
            for value in values {
                let value = value as CFTypeRef
                guard let cfRange = cfRange(from: value) else { continue }
                let nsRange = NSRange(location: cfRange.location, length: cfRange.length)
                append(nsRange, to: &ranges)
            }
        }

        return ranges
    }

    private func append(_ range: NSRange, to ranges: inout [NSRange]) {
        guard !ranges.contains(range) else { return }
        ranges.append(range)
    }

    private func selectedTextMarkerRange(from element: AXUIElement) -> AXTextMarkerRange? {
        guard let value = copiedAttribute(
            kAXSelectedTextMarkerRangeAttribute as CFString,
            from: element
        ), CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXTextMarkerRange.self)
    }

    private func nsRange(
        from markerRange: AXTextMarkerRange,
        in element: AXUIElement
    ) -> NSRange? {
        let startMarker = AXTextMarkerRangeCopyStartMarker(markerRange)
        let endMarker = AXTextMarkerRangeCopyEndMarker(markerRange)
        guard let start = markerIndex(startMarker, in: element),
              let end = markerIndex(endMarker, in: element),
              start >= 0,
              end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func markerIndex(_ marker: AXTextMarker, in element: AXUIElement) -> Int? {
        (copiedParameterizedAttribute(
            kAXIndexForTextMarkerParameterizedAttribute as CFString,
            parameter: marker,
            from: element
        ) as? NSNumber)?.intValue
    }

    private func string(for range: NSRange, in element: AXUIElement) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange),
              let value = copiedParameterizedAttribute(
                kAXStringForRangeParameterizedAttribute as CFString,
                parameter: rangeValue,
                from: element
              ) else { return nil }
        if let string = value as? String { return string }
        return (value as? NSAttributedString)?.string
    }

    private func cfRange(from value: CFTypeRef) -> CFRange? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return range
    }

    private func stringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> String? {
        guard let value = copiedAttribute(attribute, from: element) else { return nil }
        if let string = value as? String { return string }
        return (value as? NSAttributedString)?.string
    }

    private func numberAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> Int? {
        (copiedAttribute(attribute, from: element) as? NSNumber)?.intValue
    }

    private func copiedElement(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = copiedAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func copiedElements(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> [AXUIElement]? {
        guard let value = copiedAttribute(attribute, from: element),
              let values = value as? [Any] else { return nil }
        return values.compactMap { value in
            let value = value as CFTypeRef
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(value, to: AXUIElement.self)
        }
    }

    private func copiedAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private func copiedParameterizedAttribute(
        _ attribute: CFString,
        parameter: CFTypeRef,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute,
            parameter,
            &value
        ) == .success else { return nil }
        return value
    }

    /// Chromium and Electron can keep their full accessibility trees dormant
    /// until a trusted client opts in. Flow sets both application attributes;
    /// unsupported applications reject them without changing capture behavior.
    private func enableAccessibilityTree(for processID: pid_t) {
        let application = AXUIElementCreateApplication(processID)
        for attribute in [
            Self.manualAccessibilityAttribute,
            Self.enhancedUserInterfaceAttribute,
        ] {
            AXUIElementSetAttributeValue(application, attribute, kCFBooleanTrue)
        }
    }

    private var frontmostProcessID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func focusedProcessID() -> pid_t? {
        guard let element = copiedElement(
            kAXFocusedUIElementAttribute as CFString,
            from: systemWideElement
        ) else { return nil }
        var processID = pid_t()
        guard AXUIElementGetPid(element, &processID) == .success else { return nil }
        return processID
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

    private struct ElementProbe {
        let identity: AXUIElement
        let parentIdentity: AXUIElement?
        let role: String?
        let isInFocusedSubtree: Bool
        let conventionalContents: [String]
        let markerContents: String?
        let selectedTexts: [String]
        let selectedRanges: [NSRange]
        let selectedMarkerRange: AXTextMarkerRange?

        var isDirectText: Bool {
            role.map(TextContextCapture.directTextRoles.contains) ?? false
        }

        var supportsMarkerSelection: Bool {
            guard isInFocusedSubtree else { return false }
            return isDirectText
                || role == TextContextCapture.webAreaRole
                || role == kAXGroupRole
        }
    }

    private enum TraversalStep {
        case visit(
            AXUIElement,
            exploresChildren: Bool,
            exploresParent: Bool,
            isInFocusedSubtree: Bool
        )
        case evaluate(Int)
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
