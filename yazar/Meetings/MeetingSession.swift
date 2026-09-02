import AppKit
import Foundation
import Observation

/// Runs one meeting recording: the meeting-mode peer of `Yazar`.
///
/// Independent of dictation on purpose. Meeting capture never opens the
/// microphone, so `Recorder` keeps it and the dictation trigger stays live while
/// a meeting records.
@MainActor
@Observable
final class MeetingSession {
    enum State: Hashable {
        case idle
        case starting
        case recording
        case stopping
        case failed(String)
    }

    /// The activity token follows the states that are holding audio, so every
    /// path that ends or abandons a meeting also releases it. A leaked assertion
    /// keeps the Mac awake indefinitely and is visible in `pmset -g assertions`.
    private(set) var state: State = .idle {
        didSet {
            switch state {
            case .starting, .recording, .stopping:
                beginActivity()
            case .idle, .failed:
                endActivity()
            }
        }
    }

    private(set) var activeMeetingID: UUID?
    private(set) var elapsed: TimeInterval = 0

    private let store: MeetingStore
    private let recorder = SystemAudioRecorder()
    private var audioFile: MeetingAudioFile?
    private var activity: (any NSObjectProtocol)?
    private var sleepObserver: (any NSObjectProtocol)?
    private var tickTask: Task<Void, Never>?

    init(store: MeetingStore) {
        self.store = store
        recorder.onUnexpectedStop = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.finish(reason: .interrupted, failure: error.localizedDescription)
            }
        }
    }

    var isRecording: Bool {
        switch state {
        case .starting, .recording, .stopping: true
        case .idle, .failed: false
        }
    }

    /// Begins a new meeting, or continues an existing one with a fresh segment.
    func start(resuming meeting: Meeting? = nil) async {
        guard !isRecording else { return }
        state = .starting

        var subject = meeting ?? Meeting(
            title: Self.title(for: Date()),
            state: .recording,
            segments: []
        )
        subject.state = .recording
        subject.segments.append(MeetingSegment(startedAt: Date()))

        do {
            let file = try MeetingAudioFile(url: try store.audioURL(for: subject))
            audioFile = file
            // Written before capture starts so a crash during startup still
            // leaves a record for the launch scan to find.
            store.save(subject)
            activeMeetingID = subject.id
            try await recorder.start(writingTo: file)
        } catch {
            audioFile?.close()
            audioFile = nil
            activeMeetingID = nil
            // A start that captured nothing leaves no trace. Otherwise the
            // library fills with empty meetings that the next launch scan reads
            // as interrupted recordings.
            if let meeting {
                store.save(meeting)
            } else {
                store.delete(subject)
            }
            state = .failed(error.localizedDescription)
            return
        }

        state = .recording
        observeSleep()
        startTicking()
    }

    /// Closes the meeting on the way out of the process.
    ///
    /// Interrupted rather than stopped by the user: quitting ends the recording,
    /// but the meeting itself carried on without Yazar, and the transcript will
    /// need to say so.
    func endForTermination() {
        guard isRecording else { return }
        recorder.stopImmediately()
        finish(reason: .interrupted, failure: nil)
    }

    func stop() async {
        guard isRecording else { return }
        state = .stopping
        await recorder.stop()
        finish(reason: .stoppedByUser, failure: nil)
    }

    /// Closes the current segment and files the meeting.
    ///
    /// The segment is closed at the time recording actually ended, and the reason
    /// is recorded rather than inferred, because that reason is what will choose
    /// the wording of the transcript's gap marker.
    private func finish(reason: MeetingSegment.EndReason, failure: String?) {
        tickTask?.cancel()
        tickTask = nil
        stopObservingSleep()
        audioFile?.close()
        audioFile = nil

        if let id = activeMeetingID, var meeting = store.meetings.first(where: { $0.id == id }) {
            if let index = meeting.segments.indices.last, meeting.segments[index].isOpen {
                meeting.segments[index].endedAt = Date()
                meeting.segments[index].endReason = reason
            }
            // Paused rather than complete: nothing has transcribed this yet, and
            // a stopped meeting is resumable by design.
            meeting.state = reason == .interrupted ? .interrupted : .paused
            store.save(meeting)
        }

        activeMeetingID = nil
        elapsed = 0
        state = failure.map(State.failed) ?? .idle
    }

    /// macOS grants a short window before sleep. Idle sleep is already prevented
    /// by the activity token, so reaching here means a deliberate sleep, and the
    /// meeting ends cleanly rather than being left marked recording.
    private func observeSleep() {
        guard sleepObserver == nil else { return }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording else { return }
                // Synchronous: the window before sleep is short, and a record
                // left marked recording is the thing to avoid.
                self.recorder.stopImmediately()
                self.finish(reason: .interrupted, failure: nil)
            }
        }
    }

    private func stopObservingSleep() {
        guard let sleepObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        self.sleepObserver = nil
    }

    /// Drives the elapsed readout, and periodically rewrites the record so a
    /// crash loses seconds of bookkeeping rather than the whole segment.
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            var sinceFlush = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                elapsed = audioFile?.duration ?? elapsed
                if recorder.hasWriteFailure {
                    await recorder.stop()
                    finish(reason: .interrupted, failure: "Yazar could not write the meeting's audio.")
                    return
                }
                sinceFlush += 1
                if sinceFlush >= 10 {
                    sinceFlush = 0
                    flushRecord()
                }
            }
        }
    }

    private func flushRecord() {
        guard let id = activeMeetingID,
              let meeting = store.meetings.first(where: { $0.id == id }) else { return }
        store.save(meeting)
    }

    private func beginActivity() {
        guard activity == nil else { return }
        // .userInitiated already implies idleSystemSleepDisabled and disables
        // sudden termination, which is what lets applicationWillTerminate run.
        // idleDisplaySleepDisabled is deliberately not included: capture does not
        // care whether the screen is lit, and an hour of it costs battery.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Recording a meeting"
        )
    }

    private func endActivity() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    private static func title(for date: Date) -> String {
        "Meeting — \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
