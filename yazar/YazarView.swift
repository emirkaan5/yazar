import SwiftUI

/// The settings window: a page list on the left, the selected page on the right.
struct YazarView: View {
    static let minimumSize = CGSize(width: 680, height: 420)
    static let maximumSize = CGSize(width: 800, height: 520)

    @Bindable var settings: Settings
    @Bindable var permissions: Permissions
    let yazar: Yazar
    @Binding private var selection: AppPage

    init(
        settings: Settings,
        permissions: Permissions,
        yazar: Yazar,
        selection: Binding<AppPage> = .constant(.general)
    ) {
        self.settings = settings
        self.permissions = permissions
        self.yazar = yazar
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            List(AppPage.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .safeAreaPadding(.top, 30)
            .frame(width: 140)

            Divider()

            ScrollView {
                Group {
                    switch selection {
                    case .general:
                        GeneralSettingsView(settings: settings)
                    case .dictation:
                        DictationSettingsView(settings: settings, yazar: yazar)
                    case .permissions:
                        PermissionsSettingsView(
                            permissions: permissions,
                            settings: settings,
                            yazar: yazar
                        )
                    }
                }
                .frame(maxWidth: 620, alignment: .topLeading)
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(
            minWidth: Self.minimumSize.width,
            maxWidth: .infinity,
            minHeight: Self.minimumSize.height,
            maxHeight: .infinity
        )
        .ignoresSafeArea(.container)
    }
}

#Preview {
    YazarView(
        settings: Settings(),
        permissions: Permissions(),
        yazar: Yazar(settings: Settings())
    )
}
