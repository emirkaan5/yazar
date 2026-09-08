#if DEBUG
import AppKit
import Observation
import UniformTypeIdentifiers

/// Keeps live readings separate from the exact captures used for delivery.
/// Reports are bounded and memory-only; exporting is an explicit user action.
@MainActor
@Observable
final class DebugInputMonitor {
    var isPaused = false
    private(set) var liveReport = "Waiting for a focused input…"
    private(set) var reports: [DebugInputReport] = []
    private(set) var exportError: String?

    func refresh() async throws {
        let snapshot = try await TextContextCapture.refresh()
        try Task.checkCancellation()
        liveReport = snapshot.debugReport
    }

    func record(stop: TextInputSnapshot?, current: TextInputSnapshot?, transcript: String,
                output: String, decision: String) {
        let report = """
        Yazar pre-paste report — \(Date().ISO8601Format())
        Decision: \(decision)

        TRANSCRIPT
        \(transcript.debugDescription)

        OUTPUT
        \(output.debugDescription)

        RECORDING STOP
        \(stop?.debugReport ?? "No stop target captured")

        BEFORE DELIVERY
        \(current?.debugReport ?? "Not refreshed (retry or no original target)")
        """
        reports.insert(DebugInputReport(text: report), at: 0)
        if reports.count > 20 { reports.removeLast(reports.count - 20) }
    }

    func clear() {
        reports.removeAll()
        liveReport = "Cleared. Waiting for the next reading…"
        exportError = nil
    }

    func copy(_ text: String) {
        if Inserter.copy(text) == .clipboardUnavailable {
            exportError = "Could not copy the report."
        } else {
            exportError = nil
        }
    }

    func save(_ text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "yazar-input-report.txt"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                self?.exportError = nil
            } catch {
                self?.exportError = "Could not save the report: \(error.localizedDescription)"
            }
        }
    }
}
#endif
