import Foundation

/// An application the user picked for a group.
///
/// The name is stored rather than looked up, so the Formatting page can still
/// name an application the user has since uninstalled. The icon is not stored;
/// it is read from the running system where it is drawn.
struct TargetApplication: Identifiable, Codable, Hashable, Sendable {
    let bundleIdentifier: String
    var name: String

    var id: String { bundleIdentifier }

    init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }

    /// Reads a chosen application bundle. Anything without a bundle identifier
    /// cannot be matched against a running application, so it is not a target.
    init?(bundleURL: URL) {
        guard let bundleIdentifier = Bundle(url: bundleURL)?.bundleIdentifier else {
            return nil
        }
        self.bundleIdentifier = bundleIdentifier
        name = FileManager.default.displayName(atPath: bundleURL.path)
    }
}
