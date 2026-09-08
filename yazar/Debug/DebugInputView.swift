#if DEBUG
import SwiftUI

/// Inspect live input or freeze on a retained pre-paste report without losing
/// the reports when focus changes to the debug controls themselves.
struct DebugInputView: View {
    @Bindable var monitor: DebugInputMonitor
    @State private var selectedReportID: UUID?

    private var displayedReport: String {
        guard let selectedReportID else { return monitor.liveReport }
        return monitor.reports.first { $0.id == selectedReportID }?.text ?? "This report has expired. Select another report."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Capture", selection: $selectedReportID) {
                    Text("Live input").tag(nil as UUID?)
                    ForEach(monitor.reports) { report in
                        Text("Before paste · \(report.date.formatted(date: .omitted, time: .standard))")
                            .tag(Optional(report.id))
                    }
                }
                Toggle("Pause live", isOn: $monitor.isPaused)
                    .toggleStyle(.checkbox)
            }
            ScrollView([.horizontal, .vertical]) {
                Text(displayedReport)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 6))
            HStack {
                Text("Includes captured text. Last 20 paste reports kept in memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear", action: clear)
                Button("Copy") { monitor.copy(displayedReport) }
                Button("Save…") { monitor.save(displayedReport) }
            }
            if let error = monitor.exportError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(8)
    }

    private func clear() {
        selectedReportID = nil
        monitor.clear()
    }

}
#endif
