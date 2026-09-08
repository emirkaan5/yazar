import ApplicationServices
import Testing
@testable import yazar

@MainActor
@Suite("Input target identity")
struct TextInputSnapshotTests {
    @Test("Missing context does not imply a different target")
    func unavailableIdentity() {
        let original = TextInputSnapshot(processID: 42, focusedElement: AXUIElementCreateApplication(42))
        #expect(!TextInputSnapshot().targetChanged(since: original))
        #expect(!TextInputSnapshot(processID: 42).targetChanged(since: original))
        #expect(TextInputSnapshot(processID: 43).targetChanged(since: original))
    }

    @Test("Editor identity wins over a changing focused descendant")
    func stableEditor() {
        let editor = AXUIElementCreateApplication(42)
        let original = TextInputSnapshot(processID: 42, focusedElement: AXUIElementCreateApplication(43), editor: editor)
        let current = TextInputSnapshot(processID: 42, focusedElement: AXUIElementCreateApplication(44), editor: editor)
        #expect(!current.targetChanged(since: original))
        let changed = TextInputSnapshot(processID: 42, editor: AXUIElementCreateApplication(45))
        #expect(changed.targetChanged(since: original))
    }

    @Test("Only transient AX errors request a retry")
    func transientErrors() {
        let element = AXUIElementCreateApplication(42)
        let unsupported = AXReadSession()
        unsupported.record(element, attribute: "AXValue", error: .attributeUnsupported, value: nil)
        #expect(!unsupported.needsRetry)
        let transient = AXReadSession()
        transient.record(element, attribute: "AXValue", error: .cannotComplete, value: nil)
        #expect(transient.needsRetry)
        let stale = AXReadSession()
        stale.record(element, attribute: "AXValue", error: .invalidUIElement, value: nil)
        #expect(stale.needsRetry)
    }

    @Test("An expired read budget refuses more AX calls")
    func boundedReads() {
        let session = AXReadSession(budget: .zero)
        #expect(!session.prepare(AXUIElementCreateApplication(42)))
        #expect(session.expired)
    }
}
