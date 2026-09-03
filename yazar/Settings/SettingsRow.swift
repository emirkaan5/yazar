import SwiftUI

/// The shared shape of every settings page: a titled card of rows, each row a
/// label and description on the left and one control on the right.

struct SettingsSection<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    /// A card under a free-form header, for when the header carries more than a
    /// title — column labels that have to line up with the rows below it.
    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsSection where Header == SettingsSectionTitle {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(header: { SettingsSectionTitle(title) }, content: content)
    }
}

/// The title above a settings card. Its own type because a section whose header
/// carries more than a title still has to draw the title the same way.
struct SettingsSectionTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
    }
}

struct SettingsRow<Control: View>: View {
    private let title: String
    private let description: String
    private let control: Control

    init(_ title: String, description: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A settings row whose control is either a granted badge or the button that
/// asks for the grant.
struct PermissionRow: View {
    private let title: String
    private let description: String
    private let granted: Bool
    private let actionTitle: String
    private let action: () -> Void

    init(
        _ title: String,
        description: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.description = description
        self.granted = granted
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        SettingsRow(title, description: description) {
            if granted {
                GrantedLabel("Granted")
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

/// The green check used wherever a settings page reports that something is done.
struct GrantedLabel: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.green)
    }
}

struct RowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 12)
    }
}
