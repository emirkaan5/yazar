#if DEBUG
import SwiftUI

/// Tab container for development-only tools.
struct DebugPanelView: View {
    let yazar: Yazar

    var body: some View {
        TabView {
            Tab("Errors", systemImage: "exclamationmark.triangle") {
                DebugErrorsView(yazar: yazar)
            }
        }
        .padding(12)
        .frame(minWidth: 360, minHeight: 230)
    }
}
#endif
