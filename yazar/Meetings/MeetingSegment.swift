import Foundation

/// One capture run. A meeting is a list of these because `SCStream` cannot be
/// resumed: stopping and starting again produces a new stream, and the audio
/// either side of that is separated by real time nobody recorded.
nonisolated struct MeetingSegment: Codable, Hashable, Identifiable, Sendable {
    /// Why a segment stopped. This is not bookkeeping: it chooses the wording of
    /// the marker written into the assembled transcript, and the two readings are
    /// different. A user stop is a pause, and the meeting waited. An interruption
    /// is missing audio, and the meeting carried on without Yazar.
    enum EndReason: String, Codable, Hashable, Sendable {
        case stoppedByUser
        case interrupted
    }

    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var endReason: EndReason?
    /// What was said during this run. Held per segment rather than as one string
    /// on the meeting so the seams stay visible: the gap markers are derived from
    /// the segment boundaries, and a merged string has nowhere to put them.
    var transcript: String
    /// Where this run's audio begins in the meeting's file, and where it ends.
    /// The file is one contiguous append across resumes, so without these bounds
    /// there is no way to transcribe a single segment of it afterwards. Nil on
    /// segments recorded before they were tracked, and `audioEnd` is nil on one
    /// the process died holding.
    var audioStart: Int?
    var audioEnd: Int?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        endReason: EndReason? = nil,
        transcript: String = "",
        audioStart: Int? = nil,
        audioEnd: Int? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.transcript = transcript
        self.audioStart = audioStart
        self.audioEnd = audioEnd
    }

    /// Written by hand so that segments recorded before transcription existed
    /// decode as untranscribed rather than failing to decode at all.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        endReason = try container.decodeIfPresent(EndReason.self, forKey: .endReason)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        audioStart = try container.decodeIfPresent(Int.self, forKey: .audioStart)
        audioEnd = try container.decodeIfPresent(Int.self, forKey: .audioEnd)
    }

    /// An open segment is one nothing has closed yet, which after a launch scan
    /// means the process died holding it.
    var isOpen: Bool { endedAt == nil }

    var duration: TimeInterval {
        guard let endedAt else { return 0 }
        return endedAt.timeIntervalSince(startedAt)
    }
}
