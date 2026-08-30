import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    @Bindable var permissions: Permissions
    @State private var selection: SettingsPage

    private var audioInputs: [AudioInput] { AudioInput.available }

    init(
        settings: Settings,
        permissions: Permissions,
        selection: SettingsPage = .general
    ) {
        self.settings = settings
        self.permissions = permissions
        _selection = State(initialValue: selection)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 0) {
                Text(selection.title)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)

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
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 680, minHeight: 420)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if selection == .permissions {
                permissions.refresh()
                permissions.startPolling()
            }
        }
        .onChange(of: selection) { _, page in
            if page == .permissions {
                permissions.refresh()
                permissions.startPolling()
            }
        }
    }

    // Rows select on mouse-down rather than on click-up, so switching pages
    // feels immediate. A zero-distance drag is the only gesture that fires on
    // press; selection is idempotent, so repeated onChanged calls are harmless.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(SettingsPage.allCases) { page in
                Label(page.title, systemImage: page.systemImage)
					.font(.system(size: 14 ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 8)
                    .foregroundStyle(selection == page ? .primary : .secondary)
                    .background {
                        if selection == page {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color.accentColor.opacity(0.18))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in selection = page }
                    )
                    .padding(.horizontal, 8)
            }

            Spacer()
        }
        .padding(.top, 36)
        .padding(.bottom, 8)
        .frame(width: 145)
        .background(Color(nsColor: .controlBackgroundColor))
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
                TextField("Model", text: $settings.model)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
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
                description: "Sounds used for start, stop, and transcription errors."
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

            if permissions.allGranted && permissions.fnConfigured {
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

enum SettingsPage: String, CaseIterable, Identifiable {
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
    SettingsView(
        settings: Settings(),
        permissions: Permissions()
    )
}
