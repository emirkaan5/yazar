import Foundation
import Observation

@MainActor
@Observable
final class Yazar {
    enum State: Hashable {
        case idle
        case warmingUp
        case recording
        case transcribing
        case noSpeech
        case copied
        case error(DictationFailure)
    }

    // Escape capture follows the cancellable states so every path that finishes
    // or abandons a dictation releases the global key.
    private(set) var state: State = .idle {
        didSet {
            switch state {
            case .warmingUp, .recording, .transcribing:
                escapeHotKey.capture(true)
            case .idle, .noSpeech, .copied, .error:
                escapeHotKey.capture(false)
            }
        }
    }
    /// Whether the hot key is live. Starting can fail when Accessibility is
    /// missing, so the permissions screen reads this rather than assuming a
    /// granted permission means Yazar is listening.
    private(set) var isListening = false
    private(set) var level = 0.0
    private(set) var recordingStartedAt: Date?

    private let settings: Settings
    private let hotKey = HotKey()
    private let escapeHotKey = EscapeHotKey()
    private let recorder = Recorder()
    private let soundPlayer = StatusSoundPlayer()
    private var transcriptionTask: Task<Void, Never>?
    private var stateResetTask: Task<Void, Never>?
    private var recorderPollingTask: Task<Void, Never>?

    init(settings: Settings) {
        self.settings = settings
        hotKey.onPress = { [weak self] in self?.pressed() }
        hotKey.onRelease = { [weak self] in self?.released() }
        escapeHotKey.onPress = { [weak self] in self?.cancel() }
    }

    func start() throws(HotKeyError) {
        try hotKey.start()
        isListening = true
    }

    func stop() {
        hotKey.stop()
        escapeHotKey.stop()
        isListening = false
        transcriptionTask?.cancel()
        stateResetTask?.cancel()
        recorderPollingTask?.cancel()
        recorder.shutDown()
    }

    func show(_ failure: DictationFailure) {
        fail(failure)
    }

#if DEBUG
    func triggerDemoError() {
        play(.error)
        fail(.transcription("This is a demo error from Yazar."))
    }
#endif

    private func pressed() {
        switch state {
        case .idle:
            break
        case .noSpeech, .copied, .error:
            stateResetTask?.cancel()
        case .warmingUp, .recording, .transcribing:
            return
        }

        recordingStartedAt = nil
        level = 0
        state = .warmingUp
        play(.start)
        do {
            try recorder.start(inputID: settings.audioInputID)
            startPollingRecorder()
        } catch {
            fail(.recorder(error))
        }
    }

    private func released() {
        switch state {
        case .warmingUp, .recording:
            break
        case .idle, .transcribing, .noSpeech, .copied, .error:
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

    /// Drives the meter, and is also what notices a microphone that never starts
    /// or stops part-way. Without it a device unplugged mid-hold just delivers no
    /// samples, and the empty recording fails the speech gate — so a hardware
    /// problem reads to the user as "No speech".
    private func startPollingRecorder() {
        recorderPollingTask?.cancel()
        recorderPollingTask = Task { [weak self] in
            // A reused session starts in ~100 ms and the first buffer follows
            // immediately; three seconds means it is not coming.
            let firstBufferDeadline = ContinuousClock.now + .seconds(3)
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = recorder.poll()
                level = snapshot.level
                if snapshot.receivedFirstBuffer {
                    receivedFirstBuffer()
                    guard snapshot.isCapturing else {
                        fail(.recorder(.captureInterrupted))
                        return
                    }
                } else if ContinuousClock.now >= firstBufferDeadline {
                    fail(.recorder(.microphoneUnavailable))
                    return
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func finishRecording() {
        recorderPollingTask?.cancel()
        let recording = recorder.stop()
        let demoMode = isDemoMode
        play(.stop)
        recordingStartedAt = nil
        level = 0

        guard demoMode || recording.containsSpeech else {
            showNoSpeech()
            return
        }

        let transcriber = settings.transcriptionProvider.makeTranscriber(settings)
        let language = settings.optionalLanguage
        state = .transcribing
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            do {
                let text: String
#if DEBUG
                if demoMode {
                    try await Task.sleep(for: .seconds(2))
                    text = "This is a demo transcription from Yazar."
                } else {
                    text = try await transcriber.transcribe(recording, language: language)
                }
#else
                text = try await transcriber.transcribe(recording, language: language)
#endif
                try Task.checkCancellation()
                self?.deliver(text)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.play(.error)
                self?.fail(.transcription(error.localizedDescription))
            }
        }
    }

    /// Escape drops whatever is in flight. Only reachable while a dictation is
    /// running, since that is the only time the hot key is registered.
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
            play(.cancel)
            state = .idle
        case .idle, .noSpeech, .copied, .error:
            return
        }
    }

    private func fail(_ failure: DictationFailure) {
        recorderPollingTask?.cancel()
        recorder.cancel()
        transcriptionTask?.cancel()
        state = .error(failure)
        resetState(after: .seconds(2.5))
    }

    /// Paste into the focused text field when there is one; otherwise the
    /// transcription waits on the clipboard and the overlay says so, so a
    /// dictation aimed at a non-text target is never silently dropped. A
    /// provider that recognized nothing lands in the same place as audio that
    /// never cleared the speech gate.
    private func deliver(_ text: String) {
        guard !text.isEmpty else {
            showNoSpeech()
            return
        }
        switch Inserter.insert(text, restoringClipboard: settings.restoreClipboard) {
        case .pasted:
            state = .idle
        case .copied:
            state = .copied
            resetState(after: .seconds(1.6))
        case .clipboardUnavailable:
            play(.error)
            fail(.clipboardUnavailable)
        }
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

    private func play(_ status: StatusSound) {
        soundPlayer.play(status, theme: settings.soundTheme, enabled: settings.playSounds)
    }

    private var isDemoMode: Bool {
#if DEBUG
        settings.demoMode
#else
        false
#endif
    }

}
