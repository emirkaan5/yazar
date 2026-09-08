#if DEBUG
import Testing
@testable import yazar

@MainActor
@Suite("Input diagnostics")
struct DebugInputMonitorTests {
    @Test("Pre-paste reports preserve the stop and delivery context separately")
    func preservesDeliveryEvidence() {
        let monitor = DebugInputMonitor()
        let stop = TextInputSnapshot(processID: 42, context: .init(beforeText: "old", selectedText: "", afterText: ""))
        let current = TextInputSnapshot(processID: 42, context: .init(beforeText: "new", selectedText: "", afterText: " suffix"))
        monitor.record(stop: stop, current: current, transcript: "Words.", output: " words", decision: "Request paste")
        let report = monitor.reports.first?.text ?? ""
        #expect(report.contains("RECORDING STOP"))
        #expect(report.contains("BEFORE DELIVERY"))
        #expect(report.contains("\"old\""))
        #expect(report.contains("\"new\""))
        #expect(report.contains("\" words\""))
        monitor.record(stop: nil, current: nil, transcript: "Next", output: "Next", decision: "No context")
        #expect(monitor.reports[1].text == report)
    }

    @Test("Diagnostics retain only the latest twenty attempts and can be cleared")
    func boundsRetention() {
        let monitor = DebugInputMonitor()
        for index in 0..<25 {
            monitor.record(stop: nil, current: nil, transcript: "attempt-\(index)", output: "", decision: "Request paste")
        }
        #expect(monitor.reports.count == 20)
        #expect(monitor.reports.first?.text.contains("attempt-24") == true)
        #expect(monitor.reports.last?.text.contains("attempt-5") == true)
        monitor.clear()
        #expect(monitor.reports.isEmpty)
    }
}
#endif
