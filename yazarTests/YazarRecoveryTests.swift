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

    @Test("Initial delivery fits against the fresh caret rather than the recording-stop snapshot")
    func freshInsertionContext() async throws {
        let provider = DictationTestTranscriber()
        var inserted: [String] = []
        let original = TextInputSnapshot(processID: 42, context: .init(beforeText: "", selectedText: "", afterText: ""))
        let current = TextInputSnapshot(processID: 42, context: .init(beforeText: "Hello", selectedText: "", afterText: " world"))
        let yazar = Yazar(settings: settings(), makeTranscriber: { _ in provider }, insertText: {
            inserted.append($0)
            return .delivered
        }, refreshInput: { current })
        defer { yazar.stop() }
        yazar.transcribe(Recording(pcm16: Data([1, 2])), rules: [],
                         route: .init(model: .appleSpeech, language: "en"), context: original)
        try await waitUntil { await provider.recordings.count == 1 }
        await provider.reply(0, with: .success("Beautiful."))
        try await waitUntil { yazar.state == .idle }
        #expect(inserted == [" beautiful"])
    }

    @Test("An unavailable fresh context still delivers an unfitted transcript")
    func unavailableInsertionContext() async throws {
        let provider = DictationTestTranscriber()
        var inserted: [String] = []
        let original = TextInputSnapshot(processID: 42, context: .init(beforeText: "Hello", selectedText: "", afterText: " world"))
        let yazar = Yazar(settings: settings(), makeTranscriber: { _ in provider }, insertText: {
            inserted.append($0)
            return .delivered
        }, refreshInput: { TextInputSnapshot(processID: 42) })
        defer { yazar.stop() }
        yazar.transcribe(Recording(pcm16: Data([1, 2])), rules: [],
                         route: .init(model: .appleSpeech, language: "en"), context: original)
        try await waitUntil { await provider.recordings.count == 1 }
        await provider.reply(0, with: .success("Beautiful."))
        try await waitUntil { yazar.state == .idle }
        #expect(inserted == ["Beautiful."])
    }

    @Test("A changed target retains unfitted text for recovery without pasting")
    func changedInsertionTarget() async throws {
        let provider = DictationTestTranscriber()
        var inserted: [String] = []
        let yazar = Yazar(settings: settings(), makeTranscriber: { _ in provider }, insertText: {
            inserted.append($0)
            return .delivered
        }, refreshInput: { TextInputSnapshot(processID: 99) })
        defer { yazar.stop() }
        yazar.transcribe(Recording(pcm16: Data([1, 2])), rules: [],
                         route: .init(model: .appleSpeech, language: "en"),
                         context: TextInputSnapshot(processID: 42))
        try await waitUntil { await provider.recordings.count == 1 }
        await provider.reply(0, with: .success("Beautiful."))
        try await waitUntil { yazar.state == .recovery }
        #expect(inserted.isEmpty)
        guard case .text(let text) = yazar.pendingDictation else {
            Issue.record("Expected recoverable text"); return
        }
        #expect(text == "Beautiful.")
    }

    @Test("Cancellation during AX refresh prevents delivery")
    func cancelsInputRefresh() async throws {
        let provider = DictationTestTranscriber()
        var refreshing = false
        var inserted: [String] = []
        let yazar = Yazar(settings: settings(), makeTranscriber: { _ in provider }, insertText: {
            inserted.append($0)
            return .delivered
        }, refreshInput: {
            refreshing = true
            try await Task.sleep(for: .seconds(30))
            return TextInputSnapshot(processID: 42)
        })
        defer { yazar.stop() }
        yazar.transcribe(Recording(pcm16: Data([1, 2])), rules: [],
                         route: .init(model: .appleSpeech, language: "en"),
                         context: TextInputSnapshot(processID: 42))
        try await waitUntil { await provider.recordings.count == 1 }
        await provider.reply(0, with: .success("Beautiful."))
        try await waitUntil { refreshing }
        yazar.cancel()
        await Task.yield()
        #expect(yazar.state == .idle)
        #expect(inserted.isEmpty)
        #expect(yazar.pendingDictation == nil)
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
        // A failed attempt keeps the audio, with the formatting rules it was
        // captured under.
        #expect(yazar.hasRecovery)
        guard case .audio(let retained, let retainedRules, _) = yazar.pendingDictation else {
            Issue.record("Expected retained audio"); return
        }
        #expect(retained.pcm16 == audio.pcm16)
        #expect(retainedRules == [.lowercase])

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
        // A retry is audio the user already chose to keep, so it stays
        // recoverable while it runs.
        #expect(yazar.hasRecovery)
        yazar.cancel()
        #expect(yazar.state == .recovery)
        // Cancelling a retry keeps the speech, so the card can offer it again.
        guard case .audio(let retained, _, _) = yazar.pendingDictation else {
            Issue.record("Expected retained audio"); return
        }
        #expect(retained.pcm16 == audio.pcm16)
        // Closing the card in recovery is presentation only: the offer waits in
        // the menu instead of being thrown away.
        yazar.cancel()
        #expect(yazar.isRecoveryHidden)
        #expect(yazar.hasRecovery)
        yazar.revealRecovery()
        #expect(!yazar.isRecoveryHidden)
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

    @Test("Closing an error card discards it so the next trigger records")
    func dismissingErrorDiscards() async throws {
        let provider = DictationTestTranscriber()
        let yazar = Yazar(settings: settings(), makeTranscriber: { _ in provider })
        defer { yazar.stop() }
        let audio = Recording(pcm16: Data([9, 10]))
        let route = TranscriptionRoute(model: .appleSpeech, language: "en")
        yazar.transcribe(audio, rules: [], route: route)
        try await waitUntil { await provider.recordings.count == 1 }
        await provider.reply(0, with: .failure(.network))
        try await waitUntil { yazar.state == .error(.transcription(.network)) }
        #expect(yazar.hasRecovery)

        // What the card's dismiss button and Escape both do.
        yazar.cancel()
        #expect(!yazar.hasRecovery)
        #expect(!yazar.isRecoveryHidden)
        #expect(yazar.state == .idle)
        yazar.retry(using: .appleSpeech)
        #expect(await provider.recordings.count == 1)
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
        // A first attempt retains audio so a failure has something to offer,
        // but nothing has failed yet: the menu must not offer to recover it and
        // quitting must not stop to ask about it.
        #expect(!yazar.hasRecovery)
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
