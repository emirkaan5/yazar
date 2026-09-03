import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Which rewrites apply to a transcript, globally and per application group.
///
/// One card of rows under a shared set of rule columns. A group carries its
/// applications beneath its name, so adding and removing them is a click in
/// place rather than a trip through a menu.
struct FormattingSettingsView: View {
    /// Wide enough for the longest rule title. The header and every row use it,
    /// which is what keeps the checkboxes under their labels as groups are added.
    private static let ruleColumnWidth: CGFloat = 96
    /// How far every name in the card sits from the card's leading edge: the
    /// remove button's fixed width plus the gap after it. Rows without a remove
    /// button pad by it, and the application list indents by it, so the three
    /// levels line up without anyone measuring a button.
    private static let nameInset = RemoveButton.width + labelSpacing
    private static let labelSpacing: CGFloat = 6
    private static let nameFieldWidth: CGFloat = 220

    @Bindable var formatting: FormattingSettings
    @FocusState private var focusedGroup: ApplicationGroup.ID?

    var body: some View {
        SettingsSection {
            columnHeader
        } content: {
            globalRow

            ForEach($formatting.groups) { $group in
                RowDivider()
                groupBlock($group)
            }

            RowDivider()
            footer
        }
    }

    /// The section title, plus the column labels. The labels share the rows'
    /// horizontal padding, so each one lands over its own column of checkboxes.
    private var columnHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionTitle("Rules")
            columnLabels
        }
    }

    private var columnLabels: some View {
        HStack(spacing: 14) {
            Text("Applies to")
            Spacer(minLength: 8)
            ForEach(FormattingRule.allCases) { rule in
                Text(rule.title)
                    .help(rule.explanation)
                    .frame(width: Self.ruleColumnWidth)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    private var globalRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All applications")
                    .font(.system(size: 13))
                Text("Used wherever no group matches.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, Self.nameInset)

            Spacer(minLength: 8)
            ruleToggles($formatting.globalRules)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// A group's name and rules on one line, its applications listed under them.
    private func groupBlock(_ group: Binding<ApplicationGroup>) -> some View {
        let groupID = group.wrappedValue.id

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                HStack(spacing: Self.labelSpacing) {
                    RemoveButton(help: "Delete this group") {
                        formatting.groups.removeAll { $0.id == groupID }
                    }

                    // Borderless so the row reads like the global row above it.
                    TextField("Group name", text: group.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .frame(width: Self.nameFieldWidth, alignment: .leading)
                        .focused($focusedGroup, equals: groupID)
                }

                Spacer(minLength: 8)
                ruleToggles(group.rules)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(group.wrappedValue.applications) { application in
                    applicationRow(application, in: groupID)
                }

                Button {
                    addApplications(to: groupID)
                } label: {
                    Label("Add Application", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            // Indented so an application's own remove button starts exactly
            // where its group's name does.
            .padding(.leading, Self.nameInset)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func applicationRow(
        _ application: TargetApplication,
        in groupID: ApplicationGroup.ID
    ) -> some View {
        HStack(spacing: Self.labelSpacing) {
            RemoveButton(help: "Remove \(application.name) from this group") {
                remove(application, from: groupID)
            }
            ApplicationIcon(application: application)
            Text(application.name)
                .font(.system(size: 12))
        }
    }

    /// One checkbox per rule, bound straight into whichever rule set the row
    /// owns. The global row and the groups pass different sets and are otherwise
    /// identical, which is what makes them read as the same kind of thing.
    @ViewBuilder
    private func ruleToggles(_ rules: Binding<Set<FormattingRule>>) -> some View {
        ForEach(FormattingRule.allCases) { rule in
            Toggle(
                rule.title,
                isOn: Binding(
                    get: { rules.wrappedValue.contains(rule) },
                    set: { isOn in
                        if isOn {
                            rules.wrappedValue.insert(rule)
                        } else {
                            rules.wrappedValue.remove(rule)
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .help(rule.explanation)
            .frame(width: Self.ruleColumnWidth)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("A group replaces the rules above for its applications. Each application belongs to one group.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Add Group", action: addGroup)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func addGroup() {
        let group = ApplicationGroup(name: "New Group")
        formatting.groups.append(group)
        focusedGroup = group.id
    }

    /// The standard open panel is the picker. It already knows how to browse
    /// /Applications, and Yazar is not sandboxed, so reading a chosen bundle
    /// needs no further permission.
    private func addApplications(to groupID: ApplicationGroup.ID) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose the applications this group covers."
        guard panel.runModal() == .OK else { return }
        formatting.add(panel.urls.compactMap(TargetApplication.init(bundleURL:)), to: groupID)
    }

    private func remove(_ application: TargetApplication, from groupID: ApplicationGroup.ID) {
        guard let index = formatting.groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        formatting.groups[index].applications.removeAll { $0.id == application.id }
    }
}

/// Takes one thing out of the card. Used for both an application and its group,
/// so removing either reads as the same gesture at a different indent.
private struct RemoveButton: View {
    /// Fixed rather than intrinsic, because the rows that have no remove button
    /// pad by this to keep their labels on the same line as the ones that do.
    static let width: CGFloat = 16

    let help: String
    let action: () -> Void

    var body: some View {
        Button(help, systemImage: "minus.circle.fill", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 13))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .red)
            .buttonStyle(.plain)
            .frame(width: Self.width)
            .help(help)
    }
}

/// The application's icon, read from the running system rather than stored. One
/// the user has since uninstalled has no icon to read, so it keeps its place in
/// the group with a placeholder rather than vanishing from it.
private struct ApplicationIcon: View {
    let application: TargetApplication

    var body: some View {
        image
            .resizable()
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }

    private var image: Image {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: application.bundleIdentifier
        ) else {
            return Image(systemName: "questionmark.app.dashed")
        }
        return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
    }
}

#Preview {
    FormattingSettingsView(formatting: FormattingSettings())
        .frame(width: 620)
        .padding(20)
}
