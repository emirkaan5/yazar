import SwiftUI

/// The system grants and configuration Yazar needs to start listening.
struct SystemAccessSettingsView: View {
    @Bindable var permissions: Permissions
    @Bindable var settings: Settings
    let yazar: Yazar

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Permissions") {
                PermissionRow(
                    "Microphone",
                    description: "Lets Yazar record your dictation.",
                    granted: permissions.microphoneGranted,
                    actionTitle: "Request",
                    action: permissions.requestMicrophone
                )

                RowDivider()

                PermissionRow(
                    "Accessibility",
                    description: "Lets Yazar detect the dictation key and insert text.",
                    granted: permissions.accessibilityGranted,
                    actionTitle: "Request",
                    action: permissions.requestAccessibility
                )
            }

            // Only in the way when the Globe key is the dictation key.
            if settings.dictationTrigger.usesFn {
                SettingsSection("Keyboard") {
                    PermissionRow(
                        "Globe key",
                        description: "Set “Press 🌐 key to” to “Do Nothing”.",
                        granted: permissions.fnConfigured,
                        actionTitle: "Open Settings",
                        action: permissions.openKeyboardSettings
                    )
                }
            }

            if yazar.isListening {
                SettingsSection("Status") {
                    SettingsRow(
                        "Ready to use",
                        description: "Yazar is listening for the dictation key."
                    ) {
                        GrantedLabel("Listening")
                    }
                }
            } else if permissions.allGranted &&
                        (!settings.dictationTrigger.usesFn || permissions.fnConfigured) {
                SettingsSection("Status") {
                    SettingsRow(
                        "Ready to use",
                        description: "Yazar could not claim the dictation key. Relaunch to try again."
                    ) {
                        Button("Relaunch") { permissions.relaunch() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .onAppear { permissions.refresh() }
    }
}
