import SwiftUI

/// The grants Yazar needs, and whether it actually managed to start listening.
struct PermissionsSettingsView: View {
    @Bindable var permissions: Permissions
    @Bindable var settings: Settings
    let yazar: Yazar

    var body: some View {
        SettingsSection("System access") {
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

            // Only in the way when the Globe key is the dictation key.
            if settings.dictationTrigger.usesFn {
                RowDivider()

                PermissionRow(
                    "Globe key",
                    description: "Set “Press 🌐 key to” to “Do Nothing”.",
                    granted: permissions.fnConfigured,
                    actionTitle: "Open Settings",
                    action: permissions.openKeyboardSettings
                )
            }

            if yazar.isListening {
                RowDivider()

                SettingsRow(
                    "Ready to use",
                    description: "Yazar is listening for the dictation key."
                ) {
                    GrantedLabel("Listening")
                }
            } else if permissions.isReady(for: settings.dictationTrigger) {
                RowDivider()

                SettingsRow(
                    "Ready to use",
                    description: "Yazar could not claim the dictation key. Relaunch to try again."
                ) {
                    Button("Relaunch") { permissions.relaunch() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear { permissions.refresh() }
    }
}
