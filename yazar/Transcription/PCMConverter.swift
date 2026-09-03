import AVFoundation
import Foundation

/// Converts Yazar's canonical 16 kHz mono PCM into whatever format a speech
/// module wants, reusing one `AVAudioConverter` across every buffer.
///
/// Reuse is the point. A long meeting hands over samples every few hundred
/// milliseconds for an hour, and building a converter per buffer would both cost
/// more than the conversion and restart resampling from scratch each time.
///
/// Confined to whichever task feeds it, the same way `CaptureSink` is confined
/// to the capture queue, which is what the unchecked conformance stands on.
nonisolated final class PCMConverter: @unchecked Sendable {
    // Fixed 16 kHz mono LPCM. These arguments are always valid, so the
    // initialiser cannot fail.
    static let canonicalFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(Recording.sampleRate),
        channels: 1,
        interleaved: true
    )!

    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init(to outputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: Self.canonicalFormat, to: outputFormat) else {
            throw PCMConverterError.unsupportedFormat
        }
        self.converter = converter
        self.outputFormat = outputFormat
    }

    /// Converts one run of canonical samples. Returns nil for an empty or
    /// part-sample input, which is not a failure: the next call carries on.
    func convert(_ pcm16: Data) throws -> AVAudioPCMBuffer? {
        let frameCount = pcm16.count / MemoryLayout<Int16>.size
        guard frameCount > 0, frameCount <= Int(AVAudioFrameCount.max) else { return nil }

        guard let source = AVAudioPCMBuffer(
            pcmFormat: Self.canonicalFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let samples = source.int16ChannelData?[0] else {
            throw PCMConverterError.allocationFailed
        }
        pcm16.copyBytes(
            to: UnsafeMutableRawBufferPointer(
                start: samples,
                count: frameCount * MemoryLayout<Int16>.size
            )
        )
        source.frameLength = AVAudioFrameCount(frameCount)

        let ratio = outputFormat.sampleRate / Self.canonicalFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(frameCount) * ratio)) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw PCMConverterError.allocationFailed
        }

        // AVAudioConverterInputBlock is marked @Sendable, but the converter runs
        // it synchronously before `convert` returns, so nothing crosses a boundary.
        nonisolated(unsafe) let input = source
        nonisolated(unsafe) var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                // noDataNow rather than endOfStream: the converter is kept for
                // the next run of samples, and a stream this ends cannot be reused.
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return input
        }
        if let conversionError { throw conversionError }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// Drains whatever the converter is still holding, once no more samples are
    /// coming. A resampler keeps a tail of frames it has not been able to place
    /// yet, and without this the last word of a recording goes with it. The
    /// converter is finished afterwards and must not be reused.
    func finish() throws -> AVAudioPCMBuffer? {
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else {
            throw PCMConverterError.allocationFailed
        }
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            inputStatus.pointee = .endOfStream
            return nil
        }
        if status == .error, let conversionError { throw conversionError }
        guard output.frameLength > 0 else { return nil }
        return output
    }
}

enum PCMConverterError: LocalizedError {
    case unsupportedFormat
    case allocationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Yazar could not convert the audio for transcription."
        case .allocationFailed: "Yazar ran out of room to convert the audio."
        }
    }
}
