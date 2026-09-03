import Foundation
import Testing
@testable import yazar

@Suite("Meeting store")
struct MeetingStoreTests {
    @Test("Closes an orphaned segment at its last recorded sample")
    func closesOrphanedSegmentFromAudioBounds() throws {
        let root = URL.temporaryDirectory.appending(
            path: "YazarMeetingStoreTests-\(UUID())",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MeetingStore(root: root)
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let meeting = Meeting(
            title: "Orphaned",
            startedAt: startedAt,
            segments: [
                MeetingSegment(startedAt: startedAt, audioStart: 32_000)
            ]
        )
        store.save(meeting)
        try Data(count: 96_000).write(to: store.audioURL(for: meeting))

        store.closeOrphanedMeetings()

        let recovered = try #require(store.meetings.first)
        let segment = try #require(recovered.segments.last)
        #expect(segment.audioEnd == 96_000)
        #expect(segment.endedAt == startedAt.addingTimeInterval(2))
        #expect(segment.endReason == .interrupted)
    }

    @Test("Deletes audio without deleting the meeting")
    func deletesOnlyAudio() throws {
        let root = URL.temporaryDirectory.appending(
            path: "YazarMeetingStoreTests-\(UUID())",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MeetingStore(root: root)
        let meeting = Meeting(title: "Transcribed")
        store.save(meeting)
        let audioURL = try store.audioURL(for: meeting)
        try Data(count: 32_000).write(to: audioURL)

        store.deleteAudio(for: meeting)

        #expect(store.audioByteCount(for: meeting) == 0)
        #expect(store.meetings.contains(where: { $0.id == meeting.id }))
    }
}
