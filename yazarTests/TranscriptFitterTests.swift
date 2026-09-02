import Foundation
import Testing
@testable import yazar

@Suite("Transcript fitter")
struct TranscriptFitterTests {
    @Test("Returns a zero-length transcript unchanged")
    func emptyTranscript() {
        #expect(fit("") == "")
    }

    @Test("Trims transcription whitespace before adding boundaries")
    func trimsTranscript() {
        #expect(fit(" \n Hello. \t") == "Hello. ")
    }

    @Test(
        "Matches a selection's initial case",
        arguments: [
            (selected: "unhelpful", transcript: "Very useful", expected: "very useful"),
            (selected: "Unhelpful", transcript: "Very useful", expected: "Very useful"),
        ]
    )
    func selectionInitialCase(selected: String, transcript: String, expected: String) {
        #expect(fit(transcript, selected: selected) == expected)
    }

    @Test(
        "Matches a selection's punctuation role",
        arguments: [
            (selected: "old wording", expected: "new wording"),
            (selected: "old wording.", expected: "new wording."),
            (selected: "old wording)", expected: "new wording."),
            (selected: "old wording,", expected: "new wording."),
        ]
    )
    func selectionPunctuation(selected: String, expected: String) {
        #expect(fit("new wording.", selected: selected) == expected)
    }

    @Test(
        "Preserves only ASCII boundary spaces from a selection",
        arguments: [
            (selected: " old", expected: " new"),
            (selected: "old ", expected: "new "),
            (selected: "     ", expected: " new "),
            (selected: "\told\t", expected: "new"),
            (selected: "\u{00A0}old\u{00A0}", expected: "new"),
        ]
    )
    func selectionBoundarySpaces(selected: String, expected: String) {
        #expect(fit("new.", selected: selected) == expected)
    }

    @Test(
        "Detects continuation before the caret",
        arguments: [
            (before: "hello", expected: " hello."),
            (before: "hello,", expected: " hello."),
            (before: "hello)", expected: " hello."),
            (before: "hello: ", expected: "hello."),
            (before: "hello.", expected: " Hello."),
            (before: "hello!", expected: " Hello."),
            (before: "", expected: "Hello."),
            (before: "   ", expected: "Hello."),
        ]
    )
    func continuationBefore(before: String, expected: String) {
        #expect(fit("Hello.", before: before, after: " Next") == expected)
    }

    @Test(
        "Detects continuation after the caret",
        arguments: [
            (after: "continuation", expected: "Hello "),
            (after: " Continuation", expected: "Hello."),
            (after: " continuing", expected: "Hello"),
            (after: ", continuing", expected: "Hello"),
            (after: ") continuing", expected: "Hello"),
            (after: ".", expected: "Hello"),
            (after: "123", expected: "Hello. "),
            (after: "", expected: "Hello. "),
        ]
    )
    func continuationAfter(after: String, expected: String) {
        #expect(fit("Hello.", after: after) == expected)
    }

    @Test(
        "Adds a leading boundary space from only the final left character",
        arguments: [
            (before: "hello", expected: " hello"),
            (before: "hello.", expected: " hello"),
            (before: "hello ", expected: "hello"),
            (before: "(", expected: "hello"),
            (before: "word-", expected: "hello"),
            (before: "word -", expected: " hello"),
            (before: "/", expected: " hello"),
            (before: "漢", expected: "hello"),
            (before: "あ", expected: "hello"),
            (before: "カ", expected: "hello"),
        ]
    )
    func leadingBoundarySpace(before: String, expected: String) {
        #expect(fit("hello", before: before, after: " Next") == expected)
    }

    @Test(
        "Adds a trailing boundary space from the untrimmed right text",
        arguments: [
            (after: "", expected: "Hello, "),
            (after: "word", expected: "Hello, "),
            (after: "7 days", expected: "Hello, "),
            (after: " word", expected: "Hello,"),
            (after: "\u{00A0}word", expected: "Hello,"),
            (after: ", word", expected: "Hello,"),
            (after: "/ word", expected: "Hello, "),
            (after: "/word", expected: "Hello,"),
        ]
    )
    func trailingBoundarySpace(after: String, expected: String) {
        #expect(fit("Hello,", after: after) == expected)
    }

    @Test(
        "Does not add an ASCII space after East Asian terminal punctuation",
        arguments: Array("。、，．！？；：…‥「」『』（）〔〕【】《》〈〉〝〞〟・")
    )
    func eastAsianTerminalPunctuation(_ punctuation: Character) {
        #expect(fit("文\(punctuation)") == "文\(punctuation)")
    }

    @Test("Scans across every boundary-bridge character")
    func boundaryBridgeCharacters() {
        for bridge in Array("—`,-/:;()[]{} ") {
            let leftResult = fit(
                "Hello.",
                before: "word\(bridge)",
                after: " Next"
            )
            #expect(
                leftResult.trimmingCharacters(in: .whitespaces) == "hello.",
                "left bridge: \(bridge)"
            )

            #expect(
                fit("Hello.", after: "\(bridge)continuation") == "Hello",
                "right bridge: \(bridge)"
            )
        }
    }

    @Test("Handles every closing or preceding punctuation character")
    func precedingPunctuationCharacters() {
        for punctuation in Array("!%),.:;>?]}") {
            #expect(
                fit("new.", selected: "old\(punctuation)") == "new.",
                "selection punctuation: \(punctuation)"
            )
            #expect(
                fit("Hello", before: String(punctuation), after: " Next") == " Hello",
                "leading punctuation: \(punctuation)"
            )
        }
    }

    @Test("Handles every operator character at both boundaries")
    func operatorCharacters() {
        for operatorCharacter in Array("\\/|-&*+=~") {
            #expect(
                fit("hello", before: String(operatorCharacter), after: " Next") == " hello",
                "single left operator: \(operatorCharacter)"
            )
            #expect(
                fit("hello", before: "word\(operatorCharacter)", after: " Next") == "hello",
                "attached left operator: \(operatorCharacter)"
            )
            #expect(
                fit("hello", before: "word \(operatorCharacter)", after: " Next") == " hello",
                "separated left operator: \(operatorCharacter)"
            )
            #expect(
                fit("Hello,", after: "\(operatorCharacter) word") == "Hello, ",
                "right operator: \(operatorCharacter)"
            )
        }
    }

    @Test("Uses Unicode letter and number categories")
    func unicodeCategories() {
        #expect(fit("Hello.", before: "λ", after: " Next") == " hello.")
        #expect(fit("Hello.", before: "Ⅷ", after: " Next") == " hello.")
        #expect(fit("Hello.", after: "漢字") == "Hello ")
        #expect(fit("Hello.", after: "Ⅷ days") == "Hello. ")
    }

    @Test("Uses only the current lines around the caret")
    func currentLinesOnly() {
        #expect(fit(
            "Hello.",
            before: "continuing text.\n",
            after: " Next\nlowercase continuation"
        ) == "Hello.")
    }

    @Test("Lowercasing changes only the first character and skips one-character output")
    func lowercaseFirstOnly() {
        #expect(fit("HELLO", before: "word", after: " Next") == " hELLO")
        #expect(fit("A", before: "word", after: " Next") == " A")
    }

    @Test("A whitespace-only nonempty transcript follows the boundary rules")
    func whitespaceOnlyTranscript() {
        #expect(fit("   ") == " ")
        #expect(fit("   ", selected: " ") == "  ")
    }

    private func fit(
        _ transcript: String,
        before: String = "",
        selected: String = "",
        after: String = ""
    ) -> String {
        TranscriptFitter.fit(
            transcript,
            to: TextInsertionContext(
                beforeText: before,
                selectedText: selected,
                afterText: after
            )
        )
    }
}
