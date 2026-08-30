import AVFoundation
import Foundation
import Speech

struct AppleSpeechTranscriber: Transcriber {
    func transcribe(_ recording: Recording, language: String?) async throws -> String {
        guard !recording.pcm16.isEmpty else { return "" }
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechTranscriberError.unavailable
        }

        let requestedLocale = language.map(Locale.init(identifier:)) ?? .current
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        ) else {
            throw AppleSpeechTranscriberError.unsupportedLanguage(
                requestedLocale.localizedString(forIdentifier: requestedLocale.identifier)
                    ?? requestedLocale.identifier
            )
        }

        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [module]
        ) {
            try await installationRequest.downloadAndInstall()
        }
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

        var suppliedInput = false
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
