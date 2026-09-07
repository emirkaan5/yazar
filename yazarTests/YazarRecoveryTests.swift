import Foundation
import Testing
@testable import yazar

@MainActor
@Suite("Dictation recovery", .serialized)
struct YazarRecoveryTests {
    private func settings() -> Settings {
        let settings = Settings(defaults: UserDefaults(suiteName: "recovery-\(UUID())")!)
        settings.playSounds = false
        return settings
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Dictation did not reach the expected state")
    }

    @Test("Switching providers preserves speech, language and formatting without changing defaults")
    func retryAcrossProviders() async throws {
        let settings = settings()
        let provider = DictationTestTranscriber()
        var routes: [TranscriptionRoute] = []
        var copied: [String] = []
        let yazar = Yazar(settings: settings, makeTranscriber: { route in
            routes.append(route)
            return provider
        }, copyText: { text in
            copied.append(text)
            return copied.count > 1 ? .delivered : .clipboardUnavailable
        })
        defer { yazar.stop() }
        let original = settings.transcription.defaultRoute
        let audio = Recording(pcm16: Data([1, 2, 3, 4]))
        let route = TranscriptionRoute(model: .openRouter("original/model"), language: "tr")
        yazar.transcribe(audio, rules: [.lowercase], route: route)
        try await waitUntil { await provider.recordings.count == 1 }
        await provider.reply(0, with: .failure(.timedOut))
        try await waitUntil { yazar.state == .error(.transcription(.timedOut)) }
        #expect(yazar.hasRecovery)
        yazar.dismissRecovery()
        #expect(yazar.isRecoveryHidden)
        yazar.revealRecovery()
        // Hiding and re-showing is presentation only: the audio is still there,
        // with the formatting rules it was captured under.
        #expect(!yazar.isRecoveryHidden)
        guard case .audio(let hidden, let hiddenRules, _) = yazar.pendingDictation else {
            Issue.record("Expected retained audio"); return
        }
        #expect(hidden.pcm16 == audio.pcm16)
        #expect(hiddenRules == [.lowercase])

        settings.transcription.language = "de"
        yazar.retry(using: .appleSpeech)
        yazar.retry(using: .appleSpeech)
        try await waitUntil { await provider.recordings.count == 2 }
        await provider.reply(1, with: .failure(.unsupportedLanguage("Turkish")))
        try await waitUntil { if case .error = yazar.state { true } else { false } }
        yazar.retry(using: .openRouter("another/model"))
        try await waitUntil { await provider.recordings.count == 3 }
        await provider.reply(2, with: .success("HELLO THERE."))
        try await waitUntil { yazar.state == .recovery }

        #expect(routes.map(\.language) == ["tr", "tr", "tr"])
        #expect(routes.map(\.model) == [.openRouter("original/model"), .appleSpeech, .openRouter("another/model")])
        #expect(await provider.recordings.map(\.pcm16) == [audio.pcm16, audio.pcm16, audio.pcm16])
        #expect(settings.transcription.defaultRoute.model == original.model)
        #expect(copied.isEmpty)
        guard case .text(let text) = yazar.pendingDictation else {
            Issue.record("Expected retained text"); return
        }
        #expect(text == "hello there.")
        yazar.copyRecoveredText()
        #expect(yazar.state == .error(.clipboardUnavailable))
        #expect(yazar.hasRecovery)
        yazar.copyRecoveredText()
        #expect(copied == [text, text])
        #expect(!yazar.hasRecovery)
        #expect(yazar.state == .copied)
        #expect(await provider.recordings.count == 3)
    }

    @Test("Clipboard failure after initial recognition retains text without another provider request")
    func initialDeliveryFailure() async throws {
        let provider = DictationTestTranscriber()
        var insertions: [String] = []
        var copies: [String] = []
        let yazar = Yazar(settings: settings(), makeTranscriber: { _ in provider }, insertText: {
            insertions.append($0)
            return .clipboardUnavailable
        }, copyText: {
            copies.append($0)
            return .delivered
        })
        defer { yazar.stop() }
        yazar.transcribe(Recording(pcm16: Data([1, 2])), rules: [],
                         route: .init(model: .appleSpeech, language: "en"))
        try await waitUntil { await provider.recordings.count == 1 }
        await provider.reply(0, with: .success("Recognized text"))
        try await waitUntil { yazar.state == .error(.clipboardUnavailable) }
        yazar.retry(using: .openRouter("unused"))
        yazar.copyRecoveredText()
        #expect(insertions == ["Recognized text"])
        #expect(copies == insertions)
        #expect(await provider.recordings.count == 1)
        #expect(!yazar.hasRecovery)
    }

    @Test("Cancelled retries keep audio and late results cannot replace a newer attempt")
    func cancellationAndLateResults() async throws {
        let provider = DictationTestTranscriber()
        let yazar = Yazar(settings: settings(), makeTranscriber: { _ in provider })
        defer { yazar.stop() }
        let audio = Recording(pcm16: Data([5, 6]))
        let route = TranscriptionRoute(model: .appleSpeech, language: "en")
        yazar.transcribe(audio, rules: [], route: route)
        try await waitUntil { await provider.recordings.count == 1 }
        await provider.reply(0, with: .failure(.network))
        try await waitUntil { yazar.state == .error(.transcription(.network)) }
        yazar.retry(using: .appleSpeech)
        try await waitUntil { await provider.recordings.count == 2 }
        yazar.cancel()
        #expect(yazar.state == .recovery)
        // Cancelling a retry keeps the speech, so the card can offer it again.
        guard case .audio(let retained, _, _) = yazar.pendingDictation else {
            Issue.record("Expected retained audio"); return
        }
        #expect(retained.pcm16 == audio.pcm16)
        yazar.retry(using: .openRouter("new/model"))
        try await waitUntil { await provider.recordings.count == 3 }
        await provider.reply(1, with: .success("OLD"))
        await provider.reply(2, with: .success("NEW"))
        try await waitUntil { yazar.state == .recovery }
        guard case .text(let text) = yazar.pendingDictation else {
            Issue.record("Expected text"); return
        }
        #expect(text == "NEW")
        yazar.discardRecovery()
        #expect(!yazar.hasRecovery)
        yazar.retry(using: .appleSpeech)
        #expect(yazar.state == .idle)
    }

    @Test("Empty recognition remains retryable; initial cancellation and stop discard")
    func emptyAndAbandoned() async throws {
        let provider = DictationTestTranscriber()
        let yazar = Yazar(settings: settings(), makeTranscriber: { _ in provider })
        defer { yazar.stop() }
        let audio = Recording(pcm16: Data([7, 8]))
        let route = TranscriptionRoute(model: .appleSpeech, language: nil)
        yazar.transcribe(audio, rules: [], route: route)
        try await waitUntil { await provider.recordings.count == 1 }
        await provider.reply(0, with: .success("  \n"))
        try await waitUntil { yazar.state == .error(.transcription(.emptyText)) }
        #expect(yazar.hasRecovery)
        yazar.discardRecovery()
        yazar.transcribe(audio, rules: [], route: route)
        try await waitUntil { await provider.recordings.count == 2 }
        yazar.cancel()
        #expect(!yazar.hasRecovery)
        await provider.reply(1, with: .success("Abandoned"))
        yazar.transcribe(audio, rules: [], route: route)
        try await waitUntil { await provider.recordings.count == 3 }
        yazar.stop()
        await provider.reply(2, with: .failure(.network))
        #expect(!yazar.hasRecovery)
        #expect(yazar.state == .idle)
    }
}
