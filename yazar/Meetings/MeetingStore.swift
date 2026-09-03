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
    /// be holding an open segment, so one found at launch is orphaned by
    /// definition rather than merely unclaimed. It closes at its own last
    /// recorded moment, never at now, since the gap after the crash was not
    /// recorded and must not look as though it was.
    func closeOrphanedMeetings() {
        for meeting in meetings {
            guard meeting.segments.contains(where: \.isOpen) else { continue }
            var recovered = meeting
            let size = audioByteCount(for: meeting)
            recovered.segments = recovered.segments.map { segment in
                guard segment.isOpen else { return segment }
                var closed = segment
                let capturedBytes = max(0, size - (segment.audioStart ?? 0))
                closed.audioEnd = size
                closed.endedAt = segment.startedAt.addingTimeInterval(
                    MeetingAudioFile.duration(forByteCount: capturedBytes)
                )
                closed.endReason = .interrupted
                return closed
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

    /// How much audio a meeting has on disk, and zero when it has none. The
    /// answer decides whether transcribing it again is even on offer.
    func audioByteCount(for meeting: Meeting) -> Int {
        guard let url = try? audioURL(for: meeting),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
        return size
    }

    /// Removes raw audio once every segment has a successful transcript. The
    /// meeting record remains; audio only exists while transcription can retry.
    func deleteAudio(for meeting: Meeting) {
        guard let url = try? audioURL(for: meeting) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func audioURL(for meeting: Meeting) throws -> URL {
        try directory(for: meeting).appending(path: "audio.pcm", directoryHint: .notDirectory)
    }

    private static func recordURL(in directory: URL) -> URL {
        directory.appending(path: "meeting.json", directoryHint: .notDirectory)
    }
}
