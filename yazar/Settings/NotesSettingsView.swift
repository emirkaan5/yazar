import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Paste or drop a transcript, and turn it into notes.
///
/// Meeting capture does not exist yet, so this page is how the notes layer is
/// driven and tested. When meetings arrive it keeps its place as the way to make
/// notes from a transcript Yazar did not record.
struct NotesSettingsView: View {
    @Bindable var settings: Settings
    @Bindable var composer: NotesComposer
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Notes") {
                SettingsRow(
                    "Model",
                    description: "OpenRouter model that writes the notes. Uses the same API key as transcription."
                ) {
                    TextField("Required", text: $settings.openRouterNotesModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                RowDivider()

                SettingsRow(
                    "Privacy",
                    description: "The whole transcript is sent to OpenRouter to make notes. Nothing is generated on this Mac."
                ) {
                    EmptyView()
                }
            }

            SettingsSection("Transcript") {
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
                if notes.isEmpty {
                    Text("The model found nothing to note in this transcript.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    if !notes.summary.isEmpty {
                        group("Summary") {
                            Text(notes.summary)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !notes.keyPoints.isEmpty {
                        group("Key points") { bullets(notes.keyPoints) }
                    }
                    if !notes.decisions.isEmpty {
                        group("Decisions") { bullets(notes.decisions) }
                    }
                    if !notes.actionItems.isEmpty {
                        group("Action items") {
                            bullets(notes.actionItems.map { item in
                                if let owner = item.owner, !owner.isEmpty {
                                    "\(owner) — \(item.text)"
                                } else {
                                    item.text
                                }
                            })
                        }
                    }

                    // Nothing is stored yet, so copying out is the only way a
                    // result survives closing this window.
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

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(items[index])
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
            }
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
