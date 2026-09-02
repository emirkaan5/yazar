import SwiftUI

/// The settings window: a page list on the left, the selected page on the right.
struct YazarView: View {
    static let minimumSize = CGSize(width: 680, height: 420)
    static let maximumSize = CGSize(width: 800, height: 520)

    @Bindable var settings: Settings
    @Bindable var permissions: Permissions
    let yazar: Yazar
    @Bindable var composer: NotesComposer
    @Binding private var selection: AppPage

    init(
        settings: Settings,
        permissions: Permissions,
        yazar: Yazar,
        composer: NotesComposer,
        selection: Binding<AppPage> = .constant(.dictation)
    ) {
        self.settings = settings
        self.permissions = permissions
        self.yazar = yazar
        self.composer = composer
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
            .frame(width: 160)

            Divider()

            ScrollView {
                Group {
                    switch selection {
                    case .dictation:
                        DictationSettingsView(settings: settings, yazar: yazar)
                    case .transcription:
                        TranscriptionSettingsView(settings: settings)
                    case .notes:
                        NotesSettingsView(settings: settings, composer: composer)
                    case .systemAccess:
                        SystemAccessSettingsView(
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
    let settings = Settings()
    let store = MeetingStore()
    YazarView(
        settings: settings,
        permissions: Permissions(),
        yazar: Yazar(settings: settings),
        composer: NotesComposer(settings: settings, store: store)
    )
}
