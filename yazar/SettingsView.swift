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
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 17)
                    .padding(.bottom, 16)

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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsPage.allCases) { page in
                Button {
                    selection = page
                } label: {
                    Label(page.title, systemImage: page.systemImage)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == page ? .primary : .secondary)
                .background {
                    if selection == page {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor.opacity(0.18))
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer()
        }
        .padding(.top, 54)
        .padding(.bottom, 10)
        .frame(width: 180)
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
                    .frame(width: 240)
            }

            if let error = settings.apiKeyError {
                rowDivider
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }

            rowDivider

            settingsRow(
                "Model",
                description: "OpenRouter model used to transcribe recordings."
            ) {
                TextField("Model", text: $settings.model)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }

            rowDivider

            settingsRow(
                "Language",
                description: "Leave blank to detect the spoken language."
            ) {
                TextField("Auto-detect", text: $settings.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
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
                .frame(width: 240)
            }

            rowDivider

            settingsRow(
                "Play sounds",
                description: "Play feedback when recording starts and stops."
            ) {
                Toggle("Play sounds", isOn: $settings.playSounds)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())

            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private func settingsRow<Control: View>(
        _ title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 16)
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
