import Foundation
import Testing
@testable import yazar

@Suite("Meeting")
struct MeetingTests {
    @Test(
        "Assembles segment transcripts with the right gap marker",
        arguments: [
            (MeetingSegment.EndReason.stoppedByUser, "[resumed after"),
            (MeetingSegment.EndReason.interrupted, "[recording interrupted"),
        ]
    )
    func assemblesTranscriptWithGapMarker(
        _ endReason: MeetingSegment.EndReason,
        _ expectedMarker: String
    ) {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let meeting = Meeting(
            title: "Two segments",
            segments: [
                MeetingSegment(
                    startedAt: start,
                    endedAt: start.addingTimeInterval(60),
                    endReason: endReason,
                    transcript: " First "
                ),
                MeetingSegment(
                    startedAt: start.addingTimeInterval(240),
                    endedAt: start.addingTimeInterval(300),
                    endReason: .stoppedByUser,
                    transcript: " Second "
                ),
            ]
        )

        #expect(meeting.transcript.hasPrefix("First\n\n\(expectedMarker)"))
        #expect(meeting.transcript.hasSuffix("\n\nSecond"))
    }

    @Test("Migrates an interrupted legacy state into the last segment")
    func migratesLegacyInterruptedState() throws {
        let data = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "title": "Legacy",
              "startedAt": 0,
              "state": "interrupted",
              "segments": [
                {
                  "id": "00000000-0000-0000-0000-000000000002",
                  "startedAt": 0,
                  "endedAt": 1
                }
              ]
            }
            """.utf8
        )

        let meeting = try JSONDecoder().decode(Meeting.self, from: data)
        let rewritten = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(meeting)) as? [String: Any]
        )

        #expect(meeting.segments.last?.endReason == .interrupted)
        #expect(meeting.wasInterrupted)
        #expect(rewritten["state"] == nil)
    }

    @Test("Derives interruption and notes from their canonical fields")
    func derivesMeetingOutcomes() {
        let emptyNotes = Notes(summary: "", keyPoints: [], decisions: [], actionItems: [])
        var meeting = Meeting(
            title: "Outcomes",
            segments: [
                MeetingSegment(
                    startedAt: .now,
                    endedAt: .now,
                    endReason: .interrupted
                )
            ],
            notes: emptyNotes
        )

        #expect(meeting.wasInterrupted)
        #expect(!meeting.hasNotes)

        meeting.notes = Notes(
            summary: "A summary",
            keyPoints: [],
            decisions: [],
            actionItems: []
        )
        #expect(meeting.hasNotes)
    }
}
