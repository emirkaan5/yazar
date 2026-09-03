import Foundation
import Testing
@testable import yazar

@Suite("Transcript formatter")
struct TranscriptFormatterTests {
    @Test("Leaves the transcript alone when no rule is enabled")
    func noRules() {
        #expect(TranscriptFormatter.apply([], to: "Hello There.") == "Hello There.")
    }

    @Test("Lowercases the whole transcript")
    func lowercase() {
        #expect(
            TranscriptFormatter.apply([.lowercase], to: "Hello There, İstanbul.")
                == "hello there, i̇stanbul."
        )
    }
}
