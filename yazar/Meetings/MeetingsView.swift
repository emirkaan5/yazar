import SwiftUI

/// The meetings library: every stored meeting on the left, the selected one on
/// the right.
struct MeetingsView: View {
    @Bindable var store: MeetingStore
    let session: MeetingSession
    let notesMaker: MeetingNotesMaker
    let transcriptMaker: MeetingTranscriptMaker
    @State private var selection: Meeting.ID?

    var body: some View {
        NavigationSplitView {
            List(store.meetings, selection: $selection) { meeting in
                row(meeting)
                    .tag(meeting.id)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let meeting = selectedMeeting {
                MeetingDetailView(
                    meeting: meeting,
                    store: store,
                    session: session,
                    notesMaker: notesMaker,
                    transcriptMaker: transcriptMaker
                )
            } else if store.meetings.isEmpty {
                ContentUnavailableView(
                    "No Meetings",
                    systemImage: "person.2.wave.2",
                    description: Text("Start a meeting from the Yazar menu.")
                )
            } else {
                ContentUnavailableView(
                    "No Meeting Selected",
                    systemImage: "sidebar.left",
                    description: Text("Choose a meeting from the list.")
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let error = store.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
    }

    private var selectedMeeting: Meeting? {
        store.meetings.first { $0.id == selection }
    }

    private func row(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(meeting.title)
                .font(.system(size: 13))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let badge = meetingBadge(
                    for: meeting,
                    activeMeetingID: session.activeMeetingID,
                    isRecording: session.isRecording,
                    isTranscribing: transcriptMaker.isWorking(on: meeting.id),
                    isMakingNotes: notesMaker.isWorking(on: meeting.id)
                ) {
                    Text(badge)
                        .foregroundStyle(.orange)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

}
