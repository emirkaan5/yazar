import Foundation
import Testing
@testable import yazar

@Suite("Meeting badge")
struct MeetingBadgeTests {
    @Test("Uses runtime work before persisted outcomes")
    func badgePriority() {
        let id = UUID()
        let interrupted = MeetingSegment(
            startedAt: .now,
            endedAt: .now,
            endReason: .interrupted
        )
        let failedMeeting = Meeting(
            id: id,
            title: "Failed",
            segments: [interrupted],
            transcriptionFailure: "Provider failed."
        )

        #expect(meetingBadge(
            for: failedMeeting,
            activeMeetingID: id,
            isRecording: true,
            isTranscribing: true,
            isMakingNotes: true
        ) == "Recording")
        #expect(meetingBadge(
            for: failedMeeting,
            activeMeetingID: id,
            isRecording: false,
            isTranscribing: true,
            isMakingNotes: true
        ) == "Transcribing")
        #expect(meetingBadge(
            for: failedMeeting,
            activeMeetingID: nil,
            isRecording: false,
            isTranscribing: true,
            isMakingNotes: true
        ) == "Transcribing")
        #expect(meetingBadge(
            for: failedMeeting,
            activeMeetingID: nil,
            isRecording: false,
            isTranscribing: false,
            isMakingNotes: true
        ) == "Making notes")
        #expect(meetingBadge(
            for: failedMeeting,
            activeMeetingID: nil,
            isRecording: false,
            isTranscribing: false,
            isMakingNotes: false
        ) == "Transcription failed")
    }

    @Test("Describes stored outcomes and leaves completed meetings unbadged")
    func storedOutcomes() {
        let interrupted = Meeting(
            title: "Interrupted",
            segments: [
                MeetingSegment(
                    startedAt: .now,
                    endedAt: .now,
                    endReason: .interrupted
                )
            ]
        )
        let noNotes = Meeting(title: "No notes")
        let complete = Meeting(
            title: "Complete",
            notes: Notes(
                summary: "Summary",
                keyPoints: [],
                decisions: [],
                actionItems: []
            )
        )

        #expect(meetingBadge(
            for: interrupted,
            activeMeetingID: nil,
            isRecording: false,
            isTranscribing: false,
            isMakingNotes: false
        ) == "Interrupted")
        #expect(meetingBadge(
            for: noNotes,
            activeMeetingID: nil,
            isRecording: false,
            isTranscribing: false,
            isMakingNotes: false
        ) == "No notes")
        #expect(meetingBadge(
            for: complete,
            activeMeetingID: nil,
            isRecording: false,
            isTranscribing: false,
            isMakingNotes: false
        ) == nil)
    }
}
