import SwiftUI

struct YazarView: View {
    static let minimumSize = CGSize(width: 680, height: 420)
    static let maximumSize = CGSize(width: 800, height: 520)

    @Bindable var settings: Settings
    @Bindable var permissions: Permissions
    @Binding private var selection: AppPage
    @State private var customModel = ""
    @State private var isAddingCustomModel = false

    private let suggestedModels = [
        "openai/gpt-transcribe",
        "mistralai/voxtral-mini-transcribe",
    ]

    private var audioInputs: [AudioInput] { AudioInput.available }

    init(
        settings: Settings,
        permissions: Permissions,
        selection: Binding<AppPage> = .constant(.general)
    ) {
        self.settings = settings
        self.permissions = permissions
        _selection = selection
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
        }
        .onChange(of: selection) { _, page in
            if page == .permissions {
                refreshPermissions()
            }
        }
    }

    private func refreshPermissions() {
        permissions.refresh()
        permissions.startPolling()
    }

    private var generalSettings: some View {
        settingsSection("OpenRouter") {
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
                Menu {
                    Section("Suggested Models") {
                        ForEach(suggestedModels, id: \.self) { model in
                            Button {
                                settings.model = model
                            } label: {
                                HStack {
                                    Text(model)
                                    if settings.model == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button("Add a Custom Model…") {
                        customModel = ""
                        isAddingCustomModel = true
                    }
                } label: {
                    Text(settings.model)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                    .frame(width: 220)
                    .alert("Add a Custom Model", isPresented: $isAddingCustomModel) {
                        TextField("Model string", text: $customModel)
                        Button("Cancel", role: .cancel) {}
                        Button("Add") {
                            settings.model = customModel.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        }
                        .disabled(customModel.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty)
                    } message: {
                        Text("Enter the OpenRouter model string.")
                    }
            }

            rowDivider

            settingsRow(
                "Language",
                description: "Leave blank to detect the spoken language."
            ) {
                TextField("Auto-detect", text: $settings.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
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
        permissions: Permissions()
    )
}
