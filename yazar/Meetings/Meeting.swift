import Foundation

/// One recorded or imported meeting, and everything derived from it.
///
/// Transcript and notes live here rather than in sibling files so that one
/// atomic write keeps them consistent with the state field beside them. Audio is
/// the exception, and stays out of line because it is large and binary.
nonisolated struct Meeting: Codable, Hashable, Identifiable, Sendable {
    /// `paused` and `interrupted` differ only in how they were reached and share
    /// a resume path. The distinction is kept because only one of them means
    /// speech went unrecorded.
    enum State: String, Codable, Hashable, Sendable {
        case recording
        case paused
        case interrupted
        case transcribing
        case makingNotes
        case complete
    }

    /// A pause shorter than this is the ordinary rhythm of a meeting and is left
    /// unmarked; longer than it, the reader needs to know time passed.
    private static let markedPause: TimeInterval = 120

    let id: UUID
    var title: String
    var startedAt: Date
    var state: State
    var segments: [MeetingSegment]
    /// Text that came from outside a recording: pasted in, or dropped as a file.
    /// A recorded meeting leaves this empty and carries its text on its segments,
    /// so there is never a question of which of the two is authoritative.
    var importedTranscript: String
    var notes: Notes?
    /// Why transcription last failed, kept with the meeting because that is
    /// where the retry is offered. A failure that lives only in the session
    /// disappears with the recording that produced it, which is exactly when it
    /// is needed.
    var transcriptionFailure: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case startedAt
        case state
        case segments
        // Named `transcript` on disk, from before recordings existed and a
        // meeting's text could only have been imported.
        case importedTranscript = "transcript"
        case notes
        case transcriptionFailure
    }

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        state: State = .complete,
        segments: [MeetingSegment] = [],
        importedTranscript: String = "",
        notes: Notes? = nil,
        transcriptionFailure: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.state = state
        self.segments = segments
        self.importedTranscript = importedTranscript
        self.notes = notes
        self.transcriptionFailure = transcriptionFailure
    }

    var endedAt: Date? {
        segments.compactMap(\.endedAt).max()
    }

    /// Recorded time, which is the sum of the segments rather than the span from
    /// first start to last end. A meeting resumed after a four-hour gap did not
    /// record for four hours.
    var recordedDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    /// The text a reader, and `NoteMaker`, should see. Imported text is used
    /// whole; a recording is assembled from its segments.
    var transcript: String {
        importedTranscript.isEmpty ? recordedTranscript : importedTranscript
    }

    /// Segment text in order, with a marker wherever the seam between two
    /// segments swallowed time.
    ///
    /// The markers are not decoration. Run together, a deliberate four-hour break
    /// and a crash that lost six minutes of speech both read as one continuous
    /// conversation, and a model asked to summarize that will invent the causal
    /// link that appears to be there.
    var recordedTranscript: String {
        var parts: [String] = []
        for (index, segment) in segments.enumerated() {
            let text = segment.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            // A marker before any text would describe a gap in nothing.
            if index > 0, !parts.isEmpty,
               let marker = Self.marker(from: segments[index - 1], to: segment) {
                parts.append(marker)
            }
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: "\n\n")
    }

    var hasNotes: Bool { notes.map { !$0.isEmpty } ?? false }

    /// How a seam reads depends on why the earlier segment ended. A user stop is
    /// a pause the meeting waited through. An interruption is speech that
    /// happened and was never captured, and saying so is the only thing that
    /// stops the notes claiming to be complete.
    private static func marker(from previous: MeetingSegment, to next: MeetingSegment) -> String? {
        guard let endedAt = previous.endedAt else { return nil }
        let gap = max(0, next.startedAt.timeIntervalSince(endedAt))
        switch previous.endReason {
        case .interrupted:
            // "Up to", because the gap is the distance between the last captured
            // sample and the resume, which bounds the loss rather than measuring it.
            return "[recording interrupted, up to \(describe(gap)) not captured]"
        case .stoppedByUser, .none:
            guard gap >= markedPause else { return nil }
            return "[resumed after \(describe(gap))]"
        }
    }

    private static func describe(_ seconds: TimeInterval) -> String {
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = seconds < 3_600
            ? [.minutes, .seconds]
            : [.hours, .minutes]
        return Duration.seconds(seconds).formatted(
            .units(allowed: allowed, width: .wide, maximumUnitCount: 2)
        )
    }
}
