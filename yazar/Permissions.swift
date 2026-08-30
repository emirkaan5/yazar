import AppKit
import AVFoundation
import ApplicationServices
import Observation
import SwiftUI

@MainActor
@Observable
final class Permissions {
    private(set) var microphoneGranted = false
    private(set) var accessibilityGranted = false
    private(set) var fnUsage = 0
    private var pollTask: Task<Void, Never>?

    var allGranted: Bool {
        microphoneGranted && accessibilityGranted
    }

    var fnConfigured: Bool { fnUsage == 0 }
    var readyToUse: Bool { allGranted && fnConfigured }

    func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        fnUsage = UserDefaults(suiteName: ".GlobalPreferences")?.integer(forKey: "AppleFnUsageType") ?? 0
    }

    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        case .denied, .restricted:
            openPrivacySettings("Privacy_Microphone")
        case .authorized:
            refresh()
        @unknown default:
            openPrivacySettings("Privacy_Microphone")
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if !AXIsProcessTrustedWithOptions(options as CFDictionary) {
            openPrivacySettings("Privacy_Accessibility")
        }
        refresh()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
    }

    func openKeyboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
