enum AppPage: CaseIterable, Identifiable {
    case general
    case dictation
    case permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .dictation: "Dictation"
        case .permissions: "Permissions"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .dictation: "waveform"
        case .permissions: "lock.shield"
        }
    }
}
