#if DEBUG
import SwiftUI

/// Tab container for development-only tools.
struct DebugPanelView: View {
    let yazar: Yazar

    var body: some View {
        TabView {
            Tab("Text Input", systemImage: "text.cursor") {
                DebugInputView(monitor: yazar.inputMonitor)
            }
            Tab("Errors", systemImage: "exclamationmark.triangle") {
                DebugErrorsView(yazar: yazar)
            }
        }
        .padding(12)
        .frame(minWidth: 560, minHeight: 380)
    }
}
#endif
