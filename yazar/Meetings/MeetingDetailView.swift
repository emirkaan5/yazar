import AppKit
import SwiftUI

/// One meeting: its notes, and the transcript they came from.
struct MeetingDetailView: View {
    let meeting: Meeting
    @Bindable var store: MeetingStore
    @State private var showsTranscript = false
    @State private var confirmsDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let notes = meeting.notes {
                    NotesView(notes: notes)
                } else {
                    Text("This meeting has no notes yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if !meeting.transcript.isEmpty {
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

    private var duration: String {
        Duration.seconds(meeting.recordedDuration)
            .formatted(.time(pattern: .hourMinute))
    }
}
