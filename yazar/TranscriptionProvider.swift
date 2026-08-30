enum TranscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case appleSpeech
    case openRouter

    var id: Self { self }

    var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .openRouter: "OpenRouter"
        }
    }
}
