import AppKit
import CoreGraphics

@MainActor
enum Inserter {
    private struct PasteboardItem {
        let values: [(NSPasteboard.PasteboardType, Data)]
    }

    static func paste(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.pasteboardItems?.map { item in
            PasteboardItem(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let insertedChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .privateState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard pasteboard.changeCount == insertedChangeCount else { return }
            pasteboard.clearContents()
            let restoredItems = snapshot.map { snapshotItem in
                let item = NSPasteboardItem()
                for (type, data) in snapshotItem.values {
                    item.setData(data, forType: type)
                }
                return item
            }
            if !restoredItems.isEmpty {
                pasteboard.writeObjects(restoredItems)
            }
        }
    }
}
