import Foundation
import Testing
@testable import yazar

@MainActor
@Suite("Formatting settings")
struct FormattingSettingsTests {
    /// A store of its own per test, so persistence is exercised without any test
    /// reading another's groups.
    private static func makeSettings() -> FormattingSettings {
        let suiteName = "formatting-tests-\(UUID().uuidString)"
        return FormattingSettings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    private static func group(
        named name: String,
        bundleIdentifiers: [String],
        rules: Set<FormattingRule>
    ) -> ApplicationGroup {
        ApplicationGroup(
            name: name,
            applications: bundleIdentifiers.map {
                TargetApplication(bundleIdentifier: $0, name: $0)
            },
            rules: rules
        )
    }

    @Test("Falls back to the global rules for an application in no group")
    func fallsBackToGlobalRules() {
        let settings = Self.makeSettings()
        settings.globalRules = [.lowercase]
        settings.groups = [Self.group(named: "Messaging", bundleIdentifiers: ["com.apple.MobileSMS"], rules: [])]

        #expect(settings.rules(for: "com.apple.mail") == [.lowercase])
        #expect(settings.rules(for: nil) == [.lowercase])
    }

    @Test("A matching group replaces the global rules rather than adding to them")
    func groupReplacesGlobalRules() {
        let settings = Self.makeSettings()
        settings.globalRules = [.lowercase]
        settings.groups = [Self.group(named: "Mail", bundleIdentifiers: ["com.apple.mail"], rules: [])]

        #expect(settings.rules(for: "com.apple.mail") == [])
    }

    @Test("Adding an application to a group takes it out of the one it was in")
    func applicationBelongsToOneGroup() {
        let settings = Self.makeSettings()
        let messaging = Self.group(named: "Messaging", bundleIdentifiers: ["com.hnc.Discord"], rules: [.lowercase])
        let work = Self.group(named: "Work", bundleIdentifiers: [], rules: [])
        settings.groups = [messaging, work]

        settings.add([TargetApplication(bundleIdentifier: "com.hnc.Discord", name: "Discord")], to: work.id)

        #expect(settings.groups[0].applications.isEmpty)
        #expect(settings.groups[1].applications.map(\.bundleIdentifier) == ["com.hnc.Discord"])
        #expect(settings.rules(for: "com.hnc.Discord") == [])
    }

    @Test("Adding to a group that no longer exists changes nothing")
    func addingToMissingGroup() {
        let settings = Self.makeSettings()
        let messaging = Self.group(named: "Messaging", bundleIdentifiers: ["com.hnc.Discord"], rules: [.lowercase])
        settings.groups = [messaging]

        settings.add(
            [TargetApplication(bundleIdentifier: "com.hnc.Discord", name: "Discord")],
            to: UUID()
        )

        #expect(settings.groups == [messaging])
    }

    @Test("Reloads the rules and groups that were stored")
    func reloadsStoredState() {
        let suiteName = "formatting-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = FormattingSettings(defaults: defaults)
        settings.globalRules = [.lowercase]
        settings.groups = [Self.group(named: "Messaging", bundleIdentifiers: ["com.hnc.Discord"], rules: [.lowercase])]

        let reloaded = FormattingSettings(defaults: defaults)
        #expect(reloaded.globalRules == [.lowercase])
        #expect(reloaded.groups == settings.groups)
    }

    @Test("Drops a stored rule it does not recognise instead of losing the group")
    func unknownStoredRule() throws {
        let json = """
        [{
            "id": "\(UUID().uuidString)",
            "name": "Messaging",
            "applications": [{"bundleIdentifier": "com.hnc.Discord", "name": "Discord"}],
            "rules": ["lowercase", "sentenceCaseFromTheFuture"]
        }]
        """
        let groups = try JSONDecoder().decode(
            [ApplicationGroup].self,
            from: Data(json.utf8)
        )

        #expect(groups.count == 1)
        #expect(groups[0].rules == [.lowercase])
    }
}
