import Foundation
import Observation

/// The formatting rules, and the application groups that scope them.
///
/// Resolution is a single lookup with no precedence to learn: an application
/// belongs to at most one group, and anything outside a group gets the global
/// rules. `add(_:to:)` is the only method here because it is the only operation
/// that has to hold that invariant — every other edit is a plain write the
/// settings page binds to.
@MainActor
@Observable
final class FormattingSettings {
    private enum Key {
        static let globalRules = "formattingGlobalRules"
        static let groups = "formattingGroups"
    }

    private let defaults: UserDefaults

    /// Applied wherever no group matches. Every rule is off until the user says
    /// otherwise.
    var globalRules: Set<FormattingRule> {
        didSet {
            defaults.set(globalRules.map(\.rawValue).sorted(), forKey: Key.globalRules)
        }
    }

    var groups: [ApplicationGroup] {
        didSet {
            guard let data = try? JSONEncoder().encode(groups) else { return }
            defaults.set(data, forKey: Key.groups)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        globalRules = FormattingRule.set(
            fromStored: defaults.stringArray(forKey: Key.globalRules) ?? []
        )
        groups = defaults.data(forKey: Key.groups)
            .flatMap { try? JSONDecoder().decode([ApplicationGroup].self, from: $0) }
            ?? []
    }

    /// The rules for the application about to receive the paste. An unknown or
    /// missing bundle identifier resolves to the global rules, so callers never
    /// have a "not configured" case to handle.
    func rules(for bundleIdentifier: String?) -> Set<FormattingRule> {
        guard let bundleIdentifier else { return globalRules }
        let group = groups.first { group in
            group.applications.contains { $0.bundleIdentifier == bundleIdentifier }
        }
        return group?.rules ?? globalRules
    }

    /// Adds applications to a group, first taking them out of every other group.
    /// An application belongs to exactly one group, so `rules(for:)` never has to
    /// choose between two of them. Adding to a group that no longer exists, or
    /// re-adding an application already in the target group, changes nothing.
    func add(_ applications: [TargetApplication], to groupID: ApplicationGroup.ID) {
        guard groups.contains(where: { $0.id == groupID }) else { return }
        let identifiers = Set(applications.map(\.bundleIdentifier))

        // Built as one value and assigned once, so the whole move persists as a
        // single write rather than one per group touched.
        var updated = groups
        for index in updated.indices {
            updated[index].applications.removeAll {
                identifiers.contains($0.bundleIdentifier)
            }
        }
        if let index = updated.firstIndex(where: { $0.id == groupID }) {
            updated[index].applications.append(contentsOf: applications)
        }
        groups = updated
    }
}
