import Foundation
import Observation

/// Every meeting on disk, one directory each.
///
/// There is deliberately no index file. An index would be a second place the
/// truth lives, free to drift from the directories it describes; enumerating
/// them costs nothing at this scale and cannot disagree with itself.
@MainActor
@Observable
final class MeetingStore {
    private(set) var meetings: [Meeting] = []
    /// Surfaced rather than logged, because a store that cannot read its own
    /// directory looks identical to a user who has never recorded anything.
    private(set) var loadError: String?

    private let root: URL

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot
        reload()
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory
            .appending(path: "Yazar", directoryHint: .isDirectory)
            .appending(path: "Meetings", directoryHint: .isDirectory)
    }

    func reload() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let directories = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            meetings = directories
                .compactMap { directory in
                    guard let data = try? Data(contentsOf: Self.recordURL(in: directory)) else { return nil }
                    return try? decoder.decode(Meeting.self, from: data)
                }
                .sorted { $0.startedAt > $1.startedAt }
            loadError = nil
        } catch {
            meetings = []
            loadError = error.localizedDescription
        }
    }

    func save(_ meeting: Meeting) {
        do {
            let directory = root.appending(path: meeting.id.uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(meeting).write(to: Self.recordURL(in: directory), options: .atomic)

            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index] = meeting
            } else {
                meetings.append(meeting)
                meetings.sort { $0.startedAt > $1.startedAt }
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func delete(_ meeting: Meeting) {
        let directory = root.appending(path: meeting.id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        meetings.removeAll { $0.id == meeting.id }
    }

    /// Closes meetings that were still recording when the process died.
    ///
    /// Sound only because Yazar enforces a single instance: no other process can
    /// be holding these, so a record left in `recording` is orphaned by
    /// definition rather than merely unclaimed. The segment is closed at its own
    /// last known time, never at now, since the gap between the crash and this
    /// launch was not recorded and must not look as though it was.
    func closeOrphanedMeetings() {
        for meeting in meetings {
            var recovered = meeting
            switch meeting.state {
            case .recording, .transcribing:
                recovered.state = .interrupted
                recovered.segments = recovered.segments.map { segment in
                    guard segment.isOpen else { return segment }
                    var closed = segment
                    closed.endedAt = segment.startedAt
                    closed.endReason = .interrupted
                    return closed
                }
            case .makingNotes:
                // Not lost audio: the recording had already ended, and only a
                // request died with the process. The meeting goes back where it
                // was, and the library offers to make its notes again.
                recovered.state = meeting.segments.last?.endReason == .interrupted
                    ? .interrupted
                    : .paused
            case .paused, .interrupted, .complete:
                continue
            }
            save(recovered)
        }
    }

    /// The directory a meeting owns, created on demand. Audio lives here beside
    /// the record rather than inside it, being large and binary.
    func directory(for meeting: Meeting) throws -> URL {
        let directory = root.appending(path: meeting.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func audioURL(for meeting: Meeting) throws -> URL {
        try directory(for: meeting).appending(path: "audio.pcm", directoryHint: .notDirectory)
    }

    private static func recordURL(in directory: URL) -> URL {
        directory.appending(path: "meeting.json", directoryHint: .notDirectory)
    }
}
