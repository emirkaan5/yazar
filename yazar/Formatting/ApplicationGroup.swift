import Foundation

/// A set of applications the user named, and the formatting rules inside them.
///
/// The ticked rules are the complete rule set for these applications, not
/// additions to the global row, so a group can switch a rule off as well as on.
struct ApplicationGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var applications: [TargetApplication]
    var rules: Set<FormattingRule>

    init(
        id: UUID = UUID(),
        name: String,
        applications: [TargetApplication] = [],
        rules: Set<FormattingRule> = []
    ) {
        self.id = id
        self.name = name
        self.applications = applications
        self.rules = rules
    }

    // Decoded by hand only so an unrecognised rule drops out instead of taking
    // the whole group with it. See `FormattingRule.set(fromStored:)`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        applications = try container.decode([TargetApplication].self, forKey: .applications)
        rules = FormattingRule.set(
            fromStored: try container.decode([String].self, forKey: .rules)
        )
    }
}
