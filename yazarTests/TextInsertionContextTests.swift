import Foundation
import Testing
@testable import yazar

@Suite("Text insertion context")
struct TextInsertionContextTests {
    @Test("Splits conventional text with UTF-16 ranges")
    func splitsConventionalText() throws {
        let context = try #require(TextInsertionContext(
            contents: "Hello beautiful world",
            selectedRange: NSRange(location: 6, length: 9),
            applicationBundleIdentifier: "com.example.editor"
        ))

        #expect(context.beforeText == "Hello ")
        #expect(context.selectedText == "beautiful")
        #expect(context.afterText == " world")
        #expect(context.applicationBundleIdentifier == "com.example.editor")
    }

    @Test("Preserves scalar boundaries inside a combining sequence")
    func preservesCombiningSequenceOffsets() throws {
        let context = try #require(TextInsertionContext(
            contents: "e\u{301}x",
            selectedRange: NSRange(location: 1, length: 1)
        ))

        #expect(context.beforeText == "e")
        #expect(context.selectedText == "\u{301}")
        #expect(context.afterText == "x")
    }

    @Test("Handles surrogate pairs as two UTF-16 code units")
    func handlesSurrogatePairs() throws {
        let selection = try #require(TextInsertionContext(
            contents: "A😀B",
            selectedRange: NSRange(location: 1, length: 2)
        ))
        let caret = try #require(TextInsertionContext(
            contents: "A😀B",
            selectedRange: NSRange(location: 3, length: 0)
        ))

        #expect(selection.beforeText == "A")
        #expect(selection.selectedText == "😀")
        #expect(selection.afterText == "B")
        #expect(caret.beforeText == "A😀")
        #expect(caret.selectedText.isEmpty)
        #expect(caret.afterText == "B")
    }

    @Test(
        "Rejects invalid UTF-16 ranges",
        arguments: [
            NSRange(location: -1, length: 0),
            NSRange(location: 0, length: -1),
            NSRange(location: 1, length: 1),
            NSRange(location: 0, length: Int.max),
            NSRange(location: Int.max, length: 1),
        ]
    )
    func rejectsInvalidRanges(_ range: NSRange) {
        #expect(TextInsertionContext(contents: "😀", selectedRange: range) == nil)
    }
}
