#if DEBUG
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Development surface for making meeting notes from an imported transcript.
struct TranscriptNotesSection: View {
    @State private var composer: NotesComposer
    @State private var isTargeted = false

    init(settings: Settings, store: MeetingStore) {
        _composer = State(wrappedValue: NotesComposer(settings: settings, store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Development") {
                VStack(alignment: .leading, spacing: 10) {
                    transcriptEditor

                    HStack(spacing: 10) {
                        Button("Choose File…", action: chooseFile)

                        Spacer()

                        if composer.state == .working {
                            ProgressView()
                                .controlSize(.small)
                            Button("Cancel") { composer.cancel() }
                        } else {
                            Button("Make Notes") { composer.generate() }
                                .keyboardShortcut(.return, modifiers: .command)
                                .disabled(!composer.canGenerate)
                        }
                    }
                }
                .padding(12)
            }

            if case .failed(let message) = composer.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notes = composer.notes {
                notesSection(notes)
            }
        }
    }

    private var transcriptEditor: some View {
        TextEditor(text: $composer.transcript)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: 160)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isTargeted ? 2 : 1
                    )
            }
            .overlay(alignment: .topLeading) {
                if !composer.hasTranscript {
                    Text("Paste a transcript, or drop a text file here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                composer.load(contentsOf: url)
                return true
            } isTargeted: { isTargeted = $0 }
    }

    private func notesSection(_ notes: Notes) -> some View {
        SettingsSection("Result") {
            VStack(alignment: .leading, spacing: 14) {
                NotesView(notes: notes)

                if !notes.isEmpty {
                    // Copying is not the only way out: generating also files the
                    // result under Meetings, but copying stays the quickest.
                    Button("Copy as Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(notes.markdown, forType: .string)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text, .utf8PlainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        composer.load(contentsOf: url)
    }
}
#endif
