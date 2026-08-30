import AVFoundation
import Foundation
import Synchronization

enum RecorderError: LocalizedError {
    case microphoneUnavailable
    case captureSetupFailed

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "Yazar could not open the microphone."
        case .captureSetupFailed: "Yazar could not set up audio capture."
        }
    }
}

/// Captures the selected input device via AVCaptureSession and hands the main actor
/// 16 kHz mono PCM. AVAudioEngine is deliberately not used: on macOS it synthesises a
/// CADefaultDeviceAggregate spanning the default input *and* output, so recording drags a
/// Bluetooth output device into the graph and the HAL logs StartIO failures. Pinning the
/// engine to one device breaks it (input and output share a single AUHAL, which then
/// reports canPerformIO == false). AVCaptureSession opens the input device alone.
final class Recorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Snapshot {
        let receivedFirstBuffer: Bool
        let level: Double
    }

    private static let sampleRate = 16_000
    // Fixed 16 kHz mono LPCM. These arguments are always valid, so the initialiser cannot fail.
    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(sampleRate),
        channels: 1,
        interleaved: true
    )!

    private let recording = Atomic(false)
    private let receivedFirstBuffer = Atomic(false)
    private let level = Atomic(0.0)

    // startRunning/stopRunning block for ~100 ms, so session control never touches the main actor.
    private let sessionQueue = DispatchQueue(label: "yazar.capture.session")
    // Sample delivery, and the barrier stop() syncs on to flush an in-flight callback.
    private let captureQueue = DispatchQueue(label: "yazar.capture.samples")

    // Main actor only.
    private var session: AVCaptureSession?
    private var sessionInputID: String?

    // captureQueue only.
    private var samples = Data()
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var outputBuffer: AVAudioPCMBuffer?

    deinit {
        session?.stopRunning()
    }

    func start(inputID: String) throws {
        recording.store(false, ordering: .sequentiallyConsistent)
        captureQueue.sync {
            samples.removeAll(keepingCapacity: true)
        }
        receivedFirstBuffer.store(false, ordering: .relaxed)
        level.store(0, ordering: .relaxed)

        if sessionInputID != inputID { discardSession() }
        let session = try self.session ?? setUpSession(inputID: inputID)
        self.session = session
        sessionInputID = inputID
        recording.store(true, ordering: .sequentiallyConsistent)
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
    }

    func poll() -> Snapshot {
        Snapshot(
            receivedFirstBuffer: receivedFirstBuffer.load(ordering: .relaxed),
            level: level.load(ordering: .relaxed)
        )
    }

    func stop() -> Data {
        recording.store(false, ordering: .sequentiallyConsistent)
        stopSession()
        let pcm = captureQueue.sync { samples }
        level.store(0, ordering: .relaxed)
        return Self.wav(from: pcm)
    }

    func cancel() {
        recording.store(false, ordering: .sequentiallyConsistent)
        stopSession()
        captureQueue.sync {
            samples.removeAll(keepingCapacity: true)
        }
        receivedFirstBuffer.store(false, ordering: .relaxed)
        level.store(0, ordering: .relaxed)
    }

    func shutDown() {
        cancel()
        discardSession()
        captureQueue.sync {
            converter = nil
            converterInputFormat = nil
            outputBuffer = nil
        }
    }

    private func discardSession() {
        guard let session else { return }
        self.session = nil
        sessionInputID = nil
        for output in session.outputs as? [AVCaptureAudioDataOutput] ?? [] {
            output.setSampleBufferDelegate(nil, queue: nil)
        }
        sessionQueue.async {
            session.stopRunning()
        }
    }

    /// Built once and reused. The microphone indicator only lights while the session runs,
    /// so start/stop bracket each recording rather than the app's lifetime.
    private func setUpSession(inputID: String) throws -> AVCaptureSession {
        let device = inputID.isEmpty ? AudioInput.defaultDevice : AudioInput.device(id: inputID)
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device) else {
            throw RecorderError.microphoneUnavailable
        }
        let output = AVCaptureAudioDataOutput()
        let session = AVCaptureSession()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecorderError.captureSetupFailed
        }
        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        return session
    }

    private func stopSession() {
        guard let session else { return }
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard recording.load(ordering: .sequentiallyConsistent),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let inputFormat = AVAudioFormat(streamDescription: streamDescription) else { return }

        var listSize = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &listSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        ) == noErr else { return }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)

        var blockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        ) == noErr, blockBuffer != nil else { return }

        // blockBuffer owns the samples the no-copy AVAudioPCMBuffer points at.
        withExtendedLifetime(blockBuffer) {
            guard let source = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                bufferListNoCopy: list,
                deallocator: nil
            ), source.frameLength > 0 else { return }
            consume(source, inputFormat: inputFormat)
        }
    }

    private func consume(_ source: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        if converter == nil || converterInputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: Self.outputFormat)
            converterInputFormat = inputFormat
            outputBuffer = nil
        }
        guard let converter else { return }

        let ratio = Self.outputFormat.sampleRate / inputFormat.sampleRate
        let needed = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio)) + 32
        if outputBuffer == nil || outputBuffer!.frameCapacity < needed {
            outputBuffer = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: needed)
        }
        guard let output = outputBuffer else { return }

        output.frameLength = 0
        var suppliedInput = false
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
              let channel = output.int16ChannelData else { return }

        let count = Int(output.frameLength)
        samples.append(
            UnsafeRawPointer(channel[0]).assumingMemoryBound(to: UInt8.self),
            count: count * MemoryLayout<Int16>.size
        )

        level.store(Self.rms(of: channel[0], count: count), ordering: .relaxed)
        receivedFirstBuffer.store(true, ordering: .relaxed)
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

    private static func wav(from pcm: Data) -> Data {
        var wav = Data(capacity: 44 + pcm.count)
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLittleEndian(UInt32(36 + pcm.count))
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt32(sampleRate))
        wav.appendLittleEndian(UInt32(sampleRate * 2))
        wav.appendLittleEndian(UInt16(2))
        wav.appendLittleEndian(UInt16(16))
        wav.append(contentsOf: "data".utf8)
        wav.appendLittleEndian(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}

private extension Data {
    mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
