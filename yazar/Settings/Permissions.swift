import AppKit
import AVFoundation
import CoreGraphics
import ApplicationServices
import Observation
import SwiftUI

@MainActor
@Observable
final class Permissions {
    private(set) var microphoneGranted = false
    private(set) var accessibilityGranted = false
    private(set) var screenRecordingGranted = false
    private(set) var fnUsage = 0
    private var pollTask: Task<Void, Never>?

    /// Screen Recording is deliberately absent: only meetings need it, and this
    /// property gates whether the dictation engine starts at all. Including an
    /// optional permission here would stop dictation working for everyone who
    /// never records a meeting.
    var allGranted: Bool {
        microphoneGranted && accessibilityGranted
    }

    var fnConfigured: Bool { fnUsage == 0 }

    func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
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

    /// Asked for when a meeting starts rather than during onboarding, since
    /// dictation never needs it. Starting a capture prompts on its own too; this
    /// is the settings screen's way in.
    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            openPrivacySettings("Privacy_ScreenCapture")
        }
        refresh()
    }

    func requestAccessibility() {
        // ApplicationServices imports kAXTrustedCheckOptionPrompt as a mutable
        // global, which Swift 6 rejects as shared mutable state. Its value is a
        // fixed, documented constant, so spell it out rather than reach for an
        // unsafe opt-out.
        let options = ["AXTrustedCheckOptionPrompt": true]
        if !AXIsProcessTrustedWithOptions(options as CFDictionary) {
            openPrivacySettings("Privacy_Accessibility")
        }
        refresh()
    }

    /// Refreshes system state until the app's current readiness gate starts the
    /// engine and stops polling. The gate owns the trigger; this object only owns
    /// the system values it can refresh.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                refresh()
            }
        }
    }

    /// A running engine no longer needs onboarding state refreshed. Permission
    /// revocation after this point remains a next-launch concern.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
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
