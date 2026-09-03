/// Describes only meeting states that need the user's attention. Runtime work
/// wins over persisted outcomes, and a finished meeting with notes is the norm.
nonisolated func meetingBadge(
    for meeting: Meeting,
    activeMeetingID: Meeting.ID?,
    isRecording: Bool,
    isTranscribing: Bool,
    isMakingNotes: Bool
) -> String? {
    if activeMeetingID == meeting.id {
        return isRecording ? "Recording" : "Transcribing"
    }
    if isTranscribing { return "Transcribing" }
    if isMakingNotes { return "Making notes" }
    if meeting.transcriptionFailure != nil { return "Transcription failed" }
    if meeting.wasInterrupted { return "Interrupted" }
    if !meeting.hasNotes { return "No notes" }
    return nil
}
