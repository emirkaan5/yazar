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
        case complete
    }

    let id: UUID
    var title: String
    var startedAt: Date
    var state: State
    var segments: [MeetingSegment]
    var transcript: String
    var notes: Notes?

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        state: State = .complete,
        segments: [MeetingSegment] = [],
        transcript: String = "",
        notes: Notes? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.state = state
        self.segments = segments
        self.transcript = transcript
        self.notes = notes
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

    var hasNotes: Bool { notes.map { !$0.isEmpty } ?? false }
}
