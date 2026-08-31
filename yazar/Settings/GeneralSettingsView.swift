import SwiftUI

/// Which provider transcribes, what it needs to do so, and in what language.
struct GeneralSettingsView: View {
    @Bindable var settings: Settings
    @State private var speechModel = AppleSpeechModel()
    @State private var customModel = ""
    @State private var isAddingCustomModel = false
    @FocusState private var customModelFocused: Bool

    // Sentinel selection for the pop-up's escape-hatch item; never reaches Settings.
    private static let customModelTag = "\u{0}add-custom-model"

    private let suggestedModels = [
        "openai/gpt-transcribe",
        "mistralai/voxtral-mini-transcribe",
    ]

    var body: some View {
        SettingsSection("Transcription") {
            SettingsRow("Provider", description: settings.transcriptionProvider.summary) {
                Picker("Provider", selection: $settings.transcriptionProvider) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            if settings.transcriptionProvider.needsAPIKey {
                RowDivider()

                SettingsRow(
                    "API key",
                    description: "Stored securely in your Mac's Keychain."
                ) {
                    SecureField("Required", text: $settings.selectedAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .frame(width: 220)
                }

                if let error = settings.apiKeyError {
                    RowDivider()
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }

            if settings.transcriptionProvider == .openRouter {
                RowDivider()

                SettingsRow(
                    "Model",
                    description: "OpenRouter model used to transcribe recordings."
                ) {
                    Picker("Model", selection: modelSelection) {
                        Section("Suggested Models") {
                            ForEach(suggestedModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }

                        if !suggestedModels.contains(settings.openRouterModel) {
                            Section("Custom Model") {
                                Text(settings.openRouterModel).tag(settings.openRouterModel)
                            }
                        }

                        Text("Add a Custom Model…").tag(Self.customModelTag)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .sheet(isPresented: $isAddingCustomModel) { customModelSheet }
                }
            }

            RowDivider()

            SettingsRow(
                "Language",
                description: settings.transcriptionProvider.languageHint
            ) {
                TextField(settings.transcriptionProvider.languagePlaceholder, text: $settings.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            if settings.transcriptionProvider == .appleSpeech {
                RowDivider()

                SettingsRow("Language model", description: speechModelDescription) {
                    speechModelControl
                }
            }
        }
        .onAppear { refreshSpeechModel() }
        .onChange(of: settings.transcriptionProvider) { _, _ in refreshSpeechModel() }
        .onChange(of: settings.language) { _, _ in refreshSpeechModel() }
    }

    // Selecting the escape-hatch item opens the sheet instead of storing the sentinel.
    private var modelSelection: Binding<String> {
        Binding {
            settings.openRouterModel
        } set: { model in
            guard model == Self.customModelTag else {
                settings.openRouterModel = model
                return
            }
            customModel = suggestedModels.contains(settings.openRouterModel)
                ? ""
                : settings.openRouterModel
            isAddingCustomModel = true
        }
    }

    private var trimmedCustomModel: String {
        customModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customModelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a Custom Model")
                    .font(.system(size: 13, weight: .semibold))
                Text("Enter the OpenRouter model string, for example openai/gpt-transcribe.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("provider/model", text: $customModel)
                .textFieldStyle(.roundedBorder)
                .focused($customModelFocused)

            HStack {
                Spacer()
                Button("Cancel") { isAddingCustomModel = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    settings.openRouterModel = trimmedCustomModel
                    isAddingCustomModel = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedCustomModel.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { customModelFocused = true }
    }

    private func refreshSpeechModel() {
        guard settings.transcriptionProvider == .appleSpeech else { return }
        speechModel.refresh(language: settings.optionalLanguage)
    }

    /// The resolved locale once Apple Speech accepts the language, so the row
    /// names the model that will run rather than what was typed; the requested
    /// language otherwise, so an unsupported one is still named.
    private var speechModelLanguage: String {
        if let locale = speechModel.locale {
            return AppleSpeechTranscriber.displayName(for: locale)
        }
        return AppleSpeechTranscriber.displayName(for: settings.optionalLanguage)
    }

    private var speechModelDescription: String {
        switch speechModel.state {
        case .checking:
            "Checking the on-device model for \(speechModelLanguage)."
        case .unsupported:
            "Apple Speech has no model for \(speechModelLanguage). Choose another language."
        case .notInstalled:
            "macOS downloads the \(speechModelLanguage) model on first use, or fetch it now."
        case .downloading:
            "Downloading the \(speechModelLanguage) model."
        case .installed:
            "The \(speechModelLanguage) model is on this Mac."
        case .failed(let message):
            message
        }
    }

    @ViewBuilder
    private var speechModelControl: some View {
        switch speechModel.state {
        case .checking, .downloading:
            ProgressView()
                .controlSize(.small)
        case .unsupported:
            Label("Unsupported", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        case .notInstalled, .failed:
            Button("Download") { speechModel.download() }
                .buttonStyle(.bordered)
        case .installed:
            GrantedLabel("Downloaded")
        }
    }
}
