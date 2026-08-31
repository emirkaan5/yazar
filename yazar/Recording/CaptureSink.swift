import AVFoundation
import Foundation

/// Accumulates one recording's worth of microphone samples in Yazar's canonical
/// format, converting whatever the input device delivers.
///
/// Every member is touched from the recorder's capture queue only: AVFoundation
/// delivers sample buffers there, and `Recorder` reaches in through
/// `captureQueue.sync` to drain or reset. That single-queue confinement is this
/// type's whole contract, which is why the unchecked conformance lives here
/// rather than on `Recorder` — session control has no business being exempt
/// from isolation checking just because sample delivery must be.
nonisolated final class CaptureSink: @unchecked Sendable {
    // Fixed 16 kHz mono LPCM. These arguments are always valid, so the initialiser cannot fail.
    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(Recording.sampleRate),
        channels: 1,
        interleaved: true
    )!

    private var samples = Data()
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var outputBuffer: AVAudioPCMBuffer?

    /// Converts `source` and appends it. Returns the RMS level of the appended
    /// frames, or nil when the conversion produced nothing.
    func append(_ source: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> Double? {
        if converter == nil || converterInputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: Self.outputFormat)
            converterInputFormat = inputFormat
            outputBuffer = nil
        }
        guard let converter else { return nil }

        let ratio = Self.outputFormat.sampleRate / inputFormat.sampleRate
        let needed = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio)) + 32
        if outputBuffer == nil || outputBuffer!.frameCapacity < needed {
            outputBuffer = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: needed)
        }
        guard let output = outputBuffer else { return nil }

        output.frameLength = 0
        // AVAudioConverterInputBlock is marked @Sendable, but the converter runs
        // it synchronously on this thread before `convert` returns, so neither
        // the flag nor the source buffer ever crosses a boundary.
        nonisolated(unsafe) let source = source
        nonisolated(unsafe) var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return source
        }
        guard conversionError == nil,
              status != .error,
              output.frameLength > 0,
              let channel = output.int16ChannelData else { return nil }

        let count = Int(output.frameLength)
        samples.append(
            UnsafeRawPointer(channel[0]).assumingMemoryBound(to: UInt8.self),
            count: count * MemoryLayout<Int16>.size
        )
        return Self.rms(of: channel[0], count: count)
    }

    /// Hands over everything captured so far. The sink stays usable afterwards;
    /// `reset()` is what clears it for the next recording.
    func drain() -> Data {
        samples
    }

    func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    /// Drops the converter and its scratch buffer. Only worth doing when the
    /// recorder is shutting down; a device change rebuilds them on the next buffer.
    func discardConverter() {
        converter = nil
        converterInputFormat = nil
        outputBuffer = nil
    }

    private static func rms(of samples: UnsafePointer<Int16>, count: Int) -> Double {
        guard count > 0 else { return 0 }
        var sum = 0.0
        for index in 0..<count {
            let sample = Double(samples[index]) / Double(Int16.max)
            sum += sample * sample
        }
        // Speech RMS sits around 0.02-0.15, so a plain linear gain leaves the
        // meter pinned near the bottom. The power curve expands the quiet end.
        return min(1, pow(sqrt(sum / Double(count)) * 6, 0.65))
    }
}

