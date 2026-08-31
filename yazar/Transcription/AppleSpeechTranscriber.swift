import AVFoundation
import Foundation
import Speech

nonisolated struct AppleSpeechTranscriber: Transcriber {
    func transcribe(_ recording: Recording, language: String?) async throws -> String {
        guard !recording.pcm16.isEmpty else { return "" }
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechTranscriberError.unavailable
        }

        guard let locale = await Self.supportedLocale(for: language) else {
            throw AppleSpeechTranscriberError.unsupportedLanguage(Self.displayName(for: language))
        }

        let module = try await Self.downloadedModule(for: locale)
        try Task.checkCancellation()

        let sourceBuffer = try makeBuffer(from: recording)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module]
        ) else {
            throw AppleSpeechTranscriberError.unavailable
        }
        let analyzerBuffer = try convert(sourceBuffer, to: analyzerFormat)

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputBuilder.yield(AnalyzerInput(buffer: analyzerBuffer))
        inputBuilder.finish()

        let analyzer = SpeechAnalyzer(modules: [module])
        return try await withTaskCancellationHandler {
            async let transcription = collectResults(from: module)
            do {
                let lastSampleTime = try await analyzer.analyzeSequence(inputSequence)
                try Task.checkCancellation()
                if let lastSampleTime {
                    try await analyzer.finalizeAndFinish(through: lastSampleTime)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                try Task.checkCancellation()
                let text = try await transcription
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private func makeBuffer(from recording: Recording) throws -> AVAudioPCMBuffer {
        let sampleCount = recording.pcm16.count / MemoryLayout<Int16>.size
        guard sampleCount <= Int(AVAudioFrameCount.max),
              let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(Recording.sampleRate),
                channels: 1,
                interleaved: true
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ),
              let samples = buffer.int16ChannelData?[0] else {
            throw AppleSpeechTranscriberError.invalidAudio
        }

        recording.pcm16.copyBytes(
            to: UnsafeMutableRawBufferPointer(
                start: samples,
                count: recording.pcm16.count
            )
        )
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        return buffer
    }

    private func convert(
        _ source: AVAudioPCMBuffer,
        to format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: source.format, to: format) else {
            throw AppleSpeechTranscriberError.invalidAudio
        }

        let frameCount = ceil(
            Double(source.frameLength) * format.sampleRate / source.format.sampleRate
        ) + 1_024
        guard frameCount <= Double(AVAudioFrameCount.max),
              let output = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            throw AppleSpeechTranscriberError.invalidAudio
        }

        // AVAudioConverterInputBlock is marked @Sendable, but the converter runs
        // it synchronously before `convert` returns, so nothing crosses a boundary.
        nonisolated(unsafe) let source = source
        nonisolated(unsafe) var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return source
        }
        guard conversionError == nil,
              status != .error,
              output.frameLength > 0 else {
            if let conversionError { throw conversionError }
            throw AppleSpeechTranscriberError.invalidAudio
        }
        return output
    }

    private func collectResults(from module: SpeechTranscriber) async throws -> String {
        var transcription = ""
        for try await result in module.results {
            transcription += String(result.text.characters)
        }
        return transcription
    }
}

// Locale resolution and asset installation are shared with the settings screen,
// which reports the same model this transcriber will use.
nonisolated extension AppleSpeechTranscriber {
    /// The locale Apple Speech transcribes `language` with, or nil when it
    /// can't. `SpeechTranscriber.supportedLocale(equivalentTo:)` normalizes any
    /// input it recognizes as a language — "tr" comes back as tr_TR even though
    /// no Turkish model exists — so membership in `supportedLocales` is the
    /// only test that reflects what actually transcribes.
    static func supportedLocale(for language: String?) async -> Locale? {
        guard let resolved = await SpeechTranscriber.supportedLocale(
            equivalentTo: requestedLocale(for: language)
        ) else { return nil }

        let supported = await SpeechTranscriber.supportedLocales
        let isSupported = supported.contains {
            $0.identifier(.bcp47) == resolved.identifier(.bcp47)
        }
        return isSupported ? resolved : nil
    }

    /// Returns the module for `locale`, first downloading its on-device model
    /// when macOS doesn't have it. The first dictation in a language pays for
    /// the download unless the settings screen already did.
    static func downloadedModule(for locale: Locale) async throws -> SpeechTranscriber {
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [module]
        ) {
            try await installationRequest.downloadAndInstall()
        }
        return module
    }

    /// Whether macOS already holds the on-device model for `locale`.
    /// `AssetInventory.status(forModules:)` reports `.installed` only for locales
    /// the app has reserved, and Yazar reserves none, so it answers `.supported`
    /// for models that are in fact on disk. `installedLocales` is the real answer.
    static func isModelInstalled(for locale: Locale) async -> Bool {
        await SpeechTranscriber.installedLocales.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
    }

    /// Names a language for the user, always in the user's own language rather
    /// than the one being named.
    static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    static func displayName(for language: String?) -> String {
        displayName(for: requestedLocale(for: language))
    }

    /// A blank language setting means "whatever this Mac is set to".
    private static func requestedLocale(for language: String?) -> Locale {
        language.map(Locale.init(identifier:)) ?? .current
    }
}

private enum AppleSpeechTranscriberError: LocalizedError {
    case unavailable
    case unsupportedLanguage(String)
    case invalidAudio

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Speech isn't available on this Mac."
        case .unsupportedLanguage(let language):
            "Apple Speech doesn't support \(language)."
        case .invalidAudio:
            "Apple Speech couldn't read the recording."
        }
    }
}
