#if DEBUG
import Foundation

/// A frozen report stays readable after live monitoring has moved to another field.
struct DebugInputReport: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}
#endif
