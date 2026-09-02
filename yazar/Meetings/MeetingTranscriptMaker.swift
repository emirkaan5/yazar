import Foundation
import Observation

/// Transcribes a meeting from the audio already on disk.
///
/// The live path transcribes while recording, so this is the road back: a
/// provider that failed part-way through a meeting, a recording the process died
/// holding, or audio captured before there was anything to transcribe it. The
/// file is read in the same small runs capture delivered, so an hour of audio
/// costs what a second of it does and a chunked provider still sees chunks.
@MainActor
@Observable
final class MeetingTranscriptMaker {
    /// One second of canonical audio, near enough to the runs `SCStream`
    /// produces that the provider sees the same shape either way.
    private nonisolated static let readSize = Recording.sampleRate * MemoryLayout<Int16>.size

    private let store: MeetingStore
    private let settings: Settings
    private let notesMaker: MeetingNotesMaker
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(store: MeetingStore, settings: Settings, notesMaker: MeetingNotesMaker) {
        self.store = store
        self.settings = settings
        self.notesMaker = notesMaker
    }

    func isWorking(on id: UUID) -> Bool {
        tasks[id] != nil
    }

    /// Transcribes one stored meeting, then makes its notes, which is the same
    /// order a live meeting goes through. Does nothing for a meeting with no
    /// audio left to read or one already being worked on.
    func make(for id: UUID) {
        guard tasks[id] == nil,
              var meeting = store.meetings.first(where: { $0.id == id }),
              let url = try? store.audioURL(for: meeting) else { return }
        let ranges = Self.ranges(in: meeting, fileSize: store.audioByteCount(for: meeting))
        guard !ranges.isEmpty else { return }

        let transcriber = settings.transcriptionProvider.makeTranscriber(settings)
        let language = settings.optionalLanguage
        let previousState = meeting.state
        meeting.transcriptionFailure = nil
        meeting.state = .transcribing
        store.save(meeting)

        tasks[id] = Task { [weak self] in
            var texts: [Int: String] = [:]
            var failure: String?
            for (index, range) in ranges {
                do {
                    texts[index] = try await Self.transcribe(
                        url,
                        range: range,
                        with: transcriber,
                        language: language
                    )
                } catch {
                    NSLog(
                        "Yazar could not transcribe a stored meeting: %@",
                        error.localizedDescription
                    )
                    failure = error.localizedDescription
                    // The rest of the meeting would fail the same way, and a
                    // transcript missing its middle is worse than one retried.
                    break
                }
            }
            self?.finish(id, previousState: previousState, texts: texts, failure: failure)
        }
    }

    private func finish(
        _ id: UUID,
        previousState: Meeting.State,
        texts: [Int: String],
        failure: String?
    ) {
        tasks[id] = nil
        guard var meeting = store.meetings.first(where: { $0.id == id }) else { return }
        for (index, text) in texts where meeting.segments.indices.contains(index) {
            meeting.segments[index].transcript = text
        }
        meeting.transcriptionFailure = failure
        meeting.state = previousState
        store.save(meeting)

        guard failure == nil, !meeting.transcript.isEmpty else { return }
        notesMaker.make(for: id)
    }

    /// Streams one stretch of the audio file through the transcriber.
    private static func transcribe(
        _ url: URL,
        range: Range<Int>,
        with transcriber: any Transcriber,
        language: String?
    ) async throws -> String {
        let (audio, continuation) = AsyncStream.makeStream(of: Data.self)
        // Detached because the reads are blocking and this type is main-actor
        // bound. The handle is opened and closed inside the task, so nothing
        // else can be holding it when the task is cancelled.
        let feeding = Task.detached { () throws in
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
                continuation.finish()
            }
            try handle.seek(toOffset: UInt64(range.lowerBound))
            var remaining = range.count
            while remaining > 0, !Task.isCancelled {
                guard let data = try handle.read(upToCount: min(remaining, readSize)),
                      !data.isEmpty else { return }
                continuation.yield(data)
                remaining -= data.count
            }
        }
        defer { feeding.cancel() }

        var text = ""
        for try await update in transcriber.transcribe(audio, language: language) {
            text += update.finalized
        }
        // Awaited after the transcript: a file that could not be read produces
        // an empty transcript rather than an error, and this is what tells the
        // two apart.
        try await feeding.value
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Where each segment's audio sits in the file.
    ///
    /// Segments recorded before those bounds were tracked have none, so a
    /// meeting with a single segment falls back to the whole file — which is
    /// every meeting recorded before this existed.
    private static func ranges(in meeting: Meeting, fileSize: Int) -> [(Int, Range<Int>)] {
        guard fileSize > 0 else { return [] }
        var ranges: [(Int, Range<Int>)] = []
        for (index, segment) in meeting.segments.enumerated() {
            guard let start = segment.audioStart else { continue }
            // An open segment has no end, and the file's is the honest one.
            let end = min(segment.audioEnd ?? fileSize, fileSize)
            guard start < end else { continue }
            ranges.append((index, start..<end))
        }
        if ranges.isEmpty, meeting.segments.count == 1 {
            ranges = [(0, 0..<fileSize)]
        }
        return ranges
    }
}
