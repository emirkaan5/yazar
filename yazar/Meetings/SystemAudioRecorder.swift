import AVFoundation
import Foundation
import ScreenCaptureKit
import Synchronization

enum SystemAudioRecorderError: LocalizedError {
    case noDisplay
    case permissionDenied
    case captureSetupFailed
    case stoppedUnexpectedly(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            "Yazar could not find a display to capture system audio from."
        case .permissionDenied:
            "Yazar needs Screen Recording permission to hear a meeting."
        case .captureSetupFailed:
            "Yazar could not start capturing system audio."
        case .stoppedUnexpectedly(let reason):
            "System audio capture stopped: \(reason)"
        }
    }
}

/// Captures what the Mac is playing, and writes it to a meeting's audio file.
///
/// System audio only. The microphone is never opened here, which is what keeps
/// meeting capture out of `Recorder`'s way: dictation can run during a meeting
/// because nothing is contending for the input device. The cost is that the
/// user's own voice is absent from what this records, since a call does not play
/// your microphone back to you.
///
/// Sample delivery is not main-actor work and lands on `captureQueue`, which is
/// the only place the sink and the file are touched.
nonisolated final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Reports a capture that ended on its own. Set before starting; called on
    /// the capture queue, so hop before touching anything isolated.
    var onUnexpectedStop: (@Sendable (SystemAudioRecorderError) -> Void)?

    /// Hands over canonical PCM as it is captured, in the same runs that go to
    /// the file, so a transcriber hears the meeting while it is happening rather
    /// than reading the file back afterwards. Called on the capture queue.
    var onSamples: (@Sendable (Data) -> Void)?

    private let captureQueue = DispatchQueue(label: "yazar.meeting.samples")
    private let sink = CaptureSink()
    private let capturing = Atomic(false)
    private let writeFailed = Atomic(false)

    private var stream: SCStream?
    private var audioFile: MeetingAudioFile?

    /// Opens `file` and starts capture. The shareable-content query is also what
    /// prompts for Screen Recording the first time, so permission is asked for
    /// at the moment a meeting starts rather than during onboarding.
    func start(writingTo file: MeetingAudioFile) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            throw SystemAudioRecorderError.permissionDenied
        }
        guard let display = content.displays.first else {
            throw SystemAudioRecorderError.noDisplay
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = Recording.sampleRate
        configuration.channelCount = 1
        // Without this, Yazar's own start and stop sounds are recorded into the
        // meeting it is starting.
        configuration.excludesCurrentProcessAudio = true
        // A filter is required even for audio, and no screen output is added
        // below, so keep the video side as small as it is allowed to be.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
        } catch {
            throw SystemAudioRecorderError.captureSetupFailed
        }

        captureQueue.sync {
            sink.reset()
            audioFile = file
        }
        writeFailed.store(false, ordering: .relaxed)
        capturing.store(true, ordering: .sequentiallyConsistent)

        do {
            try await stream.startCapture()
        } catch {
            capturing.store(false, ordering: .sequentiallyConsistent)
            captureQueue.sync { audioFile = nil }
            throw SystemAudioRecorderError.captureSetupFailed
        }
        self.stream = stream
    }

    /// Stops capture and flushes. The file is closed by whoever opened it, so a
    /// resumed meeting can append to the same one.
    func stop() async {
        capturing.store(false, ordering: .sequentiallyConsistent)
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        // A barrier: any in-flight callback has finished before the last flush.
        captureQueue.sync {
            flushLocked()
            audioFile?.synchronize()
            audioFile = nil
        }
    }

    /// Stops accepting samples and flushes, without awaiting the stream.
    ///
    /// For the two paths that cannot await: `applicationWillTerminate`, where
    /// blocking the main thread on main-actor work deadlocks, and sleep, where
    /// macOS grants only a short window. The stream teardown is fired off and
    /// left to finish or to die with the process.
    func stopImmediately() {
        capturing.store(false, ordering: .sequentiallyConsistent)
        let stream = self.stream
        self.stream = nil
        captureQueue.sync {
            flushLocked()
            audioFile?.synchronize()
            audioFile = nil
        }
        if let stream {
            Task.detached { try? await stream.stopCapture() }
        }
    }

    var isCapturing: Bool {
        capturing.load(ordering: .relaxed)
    }

    var hasWriteFailure: Bool {
        writeFailed.load(ordering: .relaxed)
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              capturing.load(ordering: .sequentiallyConsistent),
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

        // blockBuffer owns the samples the no-copy buffer points at.
        withExtendedLifetime(blockBuffer) {
            guard let source = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                bufferListNoCopy: list,
                deallocator: nil
            ), source.frameLength > 0 else { return }
            guard sink.append(source, inputFormat: inputFormat) != nil else { return }
            // Written straight through rather than pooled in memory: an hour of
            // meeting is ~115 MB, and a crash should cost the last buffer rather
            // than the recording.
            flushLocked()
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard capturing.exchange(false, ordering: .sequentiallyConsistent) else { return }
        onUnexpectedStop?(.stoppedUnexpectedly(error.localizedDescription))
    }

    /// Must be called on `captureQueue`.
    private func flushLocked() {
        guard let audioFile else { return }
        let samples = sink.drain()
        guard !samples.isEmpty else { return }
        sink.reset()
        do {
            try audioFile.append(samples)
        } catch {
            writeFailed.store(true, ordering: .relaxed)
            return
        }
        // Only what was kept is handed on, so the transcript never describes
        // audio the file does not have.
        onSamples?(samples)
    }
}
