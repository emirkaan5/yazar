import SwiftUI

struct YazarView: View {
    static let minimumSize = CGSize(width: 680, height: 420)
    static let maximumSize = CGSize(width: 800, height: 520)

    @Bindable var settings: Settings
    @Bindable var permissions: Permissions
    @Binding private var selection: AppPage
    @State private var speechModel = AppleSpeechModel()
    @State private var customModel = ""
    @State private var isAddingCustomModel = false
    @FocusState private var customModelFocused: Bool

    // Sentinel selection for the pop-up's escape-hatch item; never reaches Settings.
    private static let customModelTag = "\u{0}add-custom-model"

    private let triggerDemoError: () -> Void

    private let suggestedModels = [
        "openai/gpt-transcribe",
        "mistralai/voxtral-mini-transcribe",
    ]

    private var audioInputs: [AudioInput] { AudioInput.available }

    init(
        settings: Settings,
        permissions: Permissions,
        selection: Binding<AppPage> = .constant(.general),
        triggerDemoError: @escaping () -> Void
    ) {
        self.settings = settings
        self.permissions = permissions
        _selection = selection
        self.triggerDemoError = triggerDemoError
    }

    var body: some View {
        HStack(spacing: 0) {
            List(AppPage.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .safeAreaPadding(.top, 30)
            .frame(width: 140)

            Divider()

            ScrollView {
                Group {
                    switch selection {
                    case .general:
                        generalSettings
                    case .dictation:
                        dictationSettings
                    case .permissions:
                        permissionSettings
                    }
                }
                .frame(maxWidth: 620, alignment: .topLeading)
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            minWidth: Self.minimumSize.width,
            maxWidth: .infinity,
            minHeight: Self.minimumSize.height,
            maxHeight: .infinity
        )
        .ignoresSafeArea(.container)
        .onAppear {
            if selection == .permissions {
                refreshPermissions()
            }
            refreshSpeechModel()
        }
        .onChange(of: selection) { _, page in
            if page == .permissions {
                refreshPermissions()
            }
        }
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

    private func refreshPermissions() {
        permissions.refresh()
        permissions.startPolling()
    }

    private var generalSettings: some View {
        settingsSection("Transcription") {
            settingsRow("Provider", description: providerDescription) {
                Picker("Provider", selection: $settings.transcriptionProvider) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            if settings.transcriptionProvider == .openRouter {
                rowDivider

                settingsRow(
                    "API key",
                    description: "Stored securely in your Mac's Keychain."
                ) {
                    SecureField("Required", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .frame(width: 220)
                }

                if let error = settings.apiKeyError {
                    rowDivider
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }

                rowDivider

                settingsRow(
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

            rowDivider

            settingsRow(
                "Language",
                description: languageDescription
            ) {
                TextField(languagePlaceholder, text: $settings.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            if settings.transcriptionProvider == .appleSpeech {
                rowDivider

                settingsRow("Language model", description: speechModelDescription) {
                    speechModelControl
                }
            }
        }
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
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        }
    }

    private var providerDescription: String {
        switch settings.transcriptionProvider {
        case .appleSpeech:
            "Processes audio on this Mac. macOS may fetch a language asset on first use."
        case .openRouter:
            "Sends each recording to OpenRouter for transcription."
        }
    }

    private var languageDescription: String {
        switch settings.transcriptionProvider {
        case .appleSpeech: "Leave blank to use your Mac's current language."
        case .openRouter: "Leave blank to detect the spoken language."
        }
    }

    private var languagePlaceholder: String {
        switch settings.transcriptionProvider {
        case .appleSpeech: "System language"
        case .openRouter: "Auto-detect"
        }
    }

    private var dictationSettings: some View {
        settingsSection("Recording") {
            settingsRow(
                "Audio input",
                description: "Microphone used for dictation."
            ) {
                Picker("Audio input", selection: $settings.audioInputID) {
                    if !settings.audioInputID.isEmpty,
                       !audioInputs.contains(where: { $0.id == settings.audioInputID }) {
                        Text("Unavailable device").tag(settings.audioInputID)
                    }
                    ForEach(audioInputs) { input in
                        Text(input.name).tag(input.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            rowDivider

            settingsRow(
                "Play sounds",
                description: "Play feedback for recording and transcription status."
            ) {
                Toggle("Play sounds", isOn: $settings.playSounds)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            rowDivider

            settingsRow(
                "Sound theme",
                description: "Sounds used for start, stop, cancellation, and transcription errors."
            ) {
                Picker("Sound theme", selection: $settings.soundTheme) {
                    ForEach(SoundTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
                .disabled(!settings.playSounds)
            }

#if DEBUG
            rowDivider

            settingsRow(
                "Demo mode",
                description: "Use the microphone, wait five seconds, then paste sample text."
            ) {
                Toggle("Demo mode", isOn: $settings.demoMode)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            rowDivider

            settingsRow(
                "Error mode",
                description: "Show the error state used when transcription fails."
            ) {
                Button("Trigger error mode", action: triggerDemoError)
                    .buttonStyle(.bordered)
            }
#endif
        }
    }

    private var permissionSettings: some View {
        settingsSection("System access") {
            permissionRow(
                "Microphone",
                description: "Lets Yazar record your dictation.",
                granted: permissions.microphoneGranted,
                actionTitle: "Request",
                action: permissions.requestMicrophone
            )

            rowDivider

            permissionRow(
                "Accessibility",
                description: "Lets Yazar detect Fn and insert text.",
                granted: permissions.accessibilityGranted,
                actionTitle: "Request",
                action: permissions.requestAccessibility
            )

            rowDivider

            permissionRow(
                "Globe key",
                description: "Set “Press 🌐 key to” to “Do Nothing”.",
                granted: permissions.fnConfigured,
                actionTitle: "Open Settings",
                action: permissions.openKeyboardSettings
            )

            if permissions.readyToUse {
                rowDivider

                settingsRow(
                    "Ready to use",
                    description: "Relaunch Yazar to start listening."
                ) {
                    Button("Relaunch") { permissions.relaunch() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private func settingsRow<Control: View>(
        _ title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func permissionRow(
        _ title: String,
        description: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        settingsRow(title, description: description) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 12)
    }

}

enum AppPage: CaseIterable, Identifiable {
    case general
    case dictation
    case permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .dictation: "Dictation"
        case .permissions: "Permissions"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .dictation: "waveform"
        case .permissions: "lock.shield"
        }
    }
}

#Preview {
    YazarView(
        settings: Settings(),
        permissions: Permissions(),
        triggerDemoError: {}
    )
}
