import AppKit
import SwiftUI

/// One meeting: its notes, and the transcript they came from. While the meeting
/// is the one being recorded, the transcript in progress stands in for both.
struct MeetingDetailView: View {
    let meeting: Meeting
    @Bindable var store: MeetingStore
    let session: MeetingSession
    let notesMaker: MeetingNotesMaker
    @State private var showsTranscript = false
    @State private var confirmsDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if isLive {
                    live
                } else if let notes = meeting.notes {
                    NotesView(notes: notes)
                } else {
                    pendingNotes
                }

                if !isLive, !meeting.transcript.isEmpty {
                    DisclosureGroup("Transcript", isExpanded: $showsTranscript) {
                        Text(meeting.transcript)
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(maxWidth: 640, alignment: .topLeading)
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The meeting being recorded right now, whose text is still arriving and is
    /// therefore read from the session rather than from the stored record.
    private var isLive: Bool {
        session.activeMeetingID == meeting.id
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meeting.title)
                .font(.system(size: 18, weight: .semibold))

            HStack(spacing: 8) {
                Text(meeting.startedAt.formatted(date: .long, time: .shortened))
                if meeting.recordedDuration > 0 {
                    Text(duration)
                }
                if let badge = MeetingsView.badge(for: meeting.state) {
                    Text(badge).foregroundStyle(.orange)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if let notes = meeting.notes, !notes.isEmpty {
                    Button("Copy as Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(notes.markdown, forType: .string)
                    }
                }
                Button("Delete", role: .destructive) { confirmsDelete = true }
                    .disabled(isLive)
            }
            .confirmationDialog(
                "Delete this meeting?",
                isPresented: $confirmsDelete
            ) {
                Button("Delete", role: .destructive) { store.delete(meeting) }
            } message: {
                Text("Its transcript and notes are removed from this Mac. This cannot be undone.")
            }
        }
    }

    /// A meeting with a transcript and no notes. Notes are made automatically
    /// when a recording stops, so reaching here means the attempt failed, the app
    /// quit before it finished, or the transcript arrived some other way.
    @ViewBuilder
    private var pendingNotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            if notesMaker.isWorking(on: meeting.id) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Making notes…")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else {
                Text("This meeting has no notes yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if let failure = notesMaker.failures[meeting.id] {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                if !meeting.transcript.isEmpty {
                    Button("Make Notes") { notesMaker.make(for: meeting.id) }
                }
            }
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: session.isRecording ? "record.circle" : "ellipsis.circle")
                Text(session.isRecording ? "Recording" : "Finishing the transcript")
                if session.isRecording, session.elapsed > 0 {
                    Text(Duration.seconds(session.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(session.isRecording ? .red : .secondary)

            // The recording carries on when transcription fails, so this reads as
            // a warning about the text rather than as the meeting having stopped.
            if let failure = session.transcriptionFailure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            if session.liveTranscript.isEmpty, session.liveVolatileText.isEmpty {
                Text("Nothing yet. Only what this Mac plays is recorded, so your own voice will not appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                // The volatile tail is dimmed because it is the provider's
                // current guess and is replaced, not appended to.
                Text("\(session.liveTranscript)\(Text(session.liveVolatileText).foregroundStyle(.secondary))")
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var duration: String {
        Duration.seconds(meeting.recordedDuration)
            .formatted(.time(pattern: .hourMinute))
    }
}
