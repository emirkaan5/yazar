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
///
/// Session control is main-actor work. Sample delivery is not, and lives in `CaptureSink`;
/// `captureOutput` is the one nonisolated member, because AVFoundation calls it on
/// `captureQueue`.
final class Recorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    struct Snapshot {
        let receivedFirstBuffer: Bool
        let level: Double
    }

    private let recording = Atomic(false)
    private let receivedFirstBuffer = Atomic(false)
    private let level = Atomic(0.0)

    // startRunning/stopRunning block for ~100 ms, so session control never touches the main actor.
    private let sessionQueue = DispatchQueue(label: "yazar.capture.session")
    // Sample delivery, and the barrier stop() syncs on to flush an in-flight callback.
    private let captureQueue = DispatchQueue(label: "yazar.capture.samples")

    private let sink = CaptureSink()

    private var session: AVCaptureSession?
    private var sessionInputID: String?

    func start(inputID: String) throws {
        recording.store(false, ordering: .sequentiallyConsistent)
        captureQueue.sync { sink.reset() }
        receivedFirstBuffer.store(false, ordering: .relaxed)
        level.store(0, ordering: .relaxed)

        if sessionInputID != inputID { discardSession() }
        let session = try self.session ?? setUpSession(inputID: inputID)
        self.session = session
        sessionInputID = inputID
        recording.store(true, ordering: .sequentiallyConsistent)
        startRunning(session)
    }

    func poll() -> Snapshot {
        Snapshot(
            receivedFirstBuffer: receivedFirstBuffer.load(ordering: .relaxed),
            level: level.load(ordering: .relaxed)
        )
    }

    func stop() -> Recording {
        recording.store(false, ordering: .sequentiallyConsistent)
        stopSession()
        let pcm = captureQueue.sync { sink.drain() }
        level.store(0, ordering: .relaxed)
        return Recording(pcm16: pcm)
    }

    func cancel() {
        recording.store(false, ordering: .sequentiallyConsistent)
        stopSession()
        captureQueue.sync { sink.reset() }
        receivedFirstBuffer.store(false, ordering: .relaxed)
        level.store(0, ordering: .relaxed)
    }

    func shutDown() {
        cancel()
        discardSession()
        captureQueue.sync { sink.discardConverter() }
    }

    private func discardSession() {
        guard let session else { return }
        self.session = nil
        sessionInputID = nil
        for output in session.outputs as? [AVCaptureAudioDataOutput] ?? [] {
            output.setSampleBufferDelegate(nil, queue: nil)
        }
        stopRunning(session)
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
        stopRunning(session)
    }

    // AVCaptureSession is not Sendable, but startRunning/stopRunning are the two
    // members Apple documents as callable from any thread, and sessionQueue
    // serialises them. The unsafe binding says exactly that and nothing wider.
    private func startRunning(_ session: AVCaptureSession) {
        nonisolated(unsafe) let session = session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
    }

    private func stopRunning(_ session: AVCaptureSession) {
        nonisolated(unsafe) let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    nonisolated func captureOutput(
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
            guard let appendedLevel = sink.append(source, inputFormat: inputFormat) else { return }
            level.store(appendedLevel, ordering: .relaxed)
            receivedFirstBuffer.store(true, ordering: .relaxed)
        }
    }
}
