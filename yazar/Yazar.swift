import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class Yazar {
    enum State: Equatable {
        case idle
        case warmingUp
        case recording
        case transcribing
        case noSpeech
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var level = 0.0
    private(set) var recordingStartedAt: Date?

    private let settings: Settings
    private let hotKey = HotKey()
    private let recorder = Recorder()
    private var transcriptionTask: Task<Void, Never>?
    private var stateResetTask: Task<Void, Never>?
    private var recorderPollingTask: Task<Void, Never>?

    // Held for the app's lifetime so playback isn't cut short when the caller returns.
    private let startSound = NSSound(named: "Tink")
    private let stopSound = NSSound(named: "Pop")
    // The first play() after the output device has idled blocks its caller ~145 ms while
    // CoreAudio starts the IO context. The Fn event tap is installed on the main run loop
    // and the window server blocks on it, so that stall must not happen on the main thread.
    private let soundQueue = DispatchQueue(label: "yazar.sounds", qos: .userInitiated)

    init(settings: Settings) {
        self.settings = settings
        hotKey.onPress = { [weak self] in self?.pressed() }
        hotKey.onRelease = { [weak self] in self?.released() }
        hotKey.onCancel = { [weak self] in self?.cancel() }
    }

    func start() throws {
        try hotKey.start()
    }

    func stop() {
        hotKey.stop()
        transcriptionTask?.cancel()
        stateResetTask?.cancel()
        recorderPollingTask?.cancel()
        recorder.shutDown()
    }

    func show(error: Error) {
        showError(error.localizedDescription)
    }

    private func pressed() {
        switch state {
        case .idle:
            break
        case .noSpeech, .error:
            stateResetTask?.cancel()
        case .warmingUp, .recording, .transcribing:
            return
        }

        recordingStartedAt = nil
        level = 0
        state = .warmingUp
        play(startSound)
        do {
            try recorder.start(inputID: settings.audioInputID)
            startPollingRecorder()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func released() {
        switch state {
        case .warmingUp, .recording:
            break
        case .idle, .transcribing, .noSpeech, .error:
            return
        }

        finishRecording()
    }

    private func receivedFirstBuffer() {
        if state == .warmingUp {
            recordingStartedAt = Date()
            state = .recording
        } else if case .recording = state, recordingStartedAt == nil {
            recordingStartedAt = Date()
        }
    }

    private func startPollingRecorder() {
        recorderPollingTask?.cancel()
        recorderPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = recorder.poll()
                level = snapshot.level
                if snapshot.receivedFirstBuffer { receivedFirstBuffer() }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func finishRecording() {
        recorderPollingTask?.cancel()
        let wav = recorder.stop()
        play(stopSound)
        recordingStartedAt = nil
        level = 0

        guard Self.containsSpeech(wav) else {
            showNoSpeech()
            return
        }

        let transcriber = Transcriber(
            apiKey: settings.apiKey,
            model: settings.model,
            language: settings.optionalLanguage
        )
        state = .transcribing
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            do {
                let text = try await transcriber.transcribe(wav)
                try Task.checkCancellation()
                if !text.isEmpty { Inserter.paste(text) }
                self?.state = .idle
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.showError(error.localizedDescription)
            }
        }
    }

    private func cancel() {
        switch state {
        case .warmingUp, .recording:
            recorderPollingTask?.cancel()
            recorder.cancel()
            recordingStartedAt = nil
            level = 0
            state = .idle
        case .transcribing:
            transcriptionTask?.cancel()
            transcriptionTask = nil
            state = .idle
        case .idle, .noSpeech, .error:
            return
        }
    }

    private func showError(_ message: String) {
        recorderPollingTask?.cancel()
        recorder.cancel()
        transcriptionTask?.cancel()
        state = .error(message)
        resetState(after: .seconds(2.5))
    }

    private func showNoSpeech() {
        state = .noSpeech
        resetState(after: .seconds(1.2))
    }

    private func resetState(after delay: Duration) {
        let expectedState = state
        stateResetTask?.cancel()
        stateResetTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            guard self?.state == expectedState else { return }
            self?.state = .idle
        }
    }

    private func play(_ sound: NSSound?) {
        guard settings.playSounds, let sound else { return }
        // Pop runs 1.6 s, so tapping the hot key repeatedly re-triggers a sound that is
        // still playing. play() refuses in that case and logs "Already playing"; rewinding
        // first restarts it, which is what feedback sounds should do.
        soundQueue.async {
            sound.stop()
            sound.play()
        }
    }

    private static func containsSpeech(_ wav: Data) -> Bool {
        let sampleCount = max(0, (wav.count - 44) / MemoryLayout<Int16>.size)
        guard sampleCount >= 4_800 else { return false }

        var sum = 0.0
        wav.withUnsafeBytes { bytes in
            for index in 0..<sampleCount {
                let sample = bytes.loadUnaligned(fromByteOffset: 44 + index * 2, as: Int16.self)
                let normalized = Double(Int16(littleEndian: sample)) / Double(Int16.max)
                sum += normalized * normalized
            }
        }
        return sqrt(sum / Double(sampleCount)) > 0.003
    }
}
