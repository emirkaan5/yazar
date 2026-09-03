/// Which engine answers a chat-completion request, for the notes layer and, in
/// time, roadmap item 1's dictation cleanup.
///
/// This mirrors `TranscriptionProvider` and earns the same keep: two real cases
/// that differ in credentials and in where the text goes. It is not the
/// `NotesProvider` enum the meeting-notes plan turned down — that would have
/// been a one-case mirror of `NoteMaker`. This one sits a layer lower, under
/// `LanguageModelClient`, and knows nothing about notes.
enum LanguageModelProvider: String, CaseIterable, Identifiable, Sendable {
    case openRouter
    case local

    var id: Self { self }

    var displayName: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .local: "Local"
        }
    }

    /// What choosing this provider means for the transcript.
    var summary: String {
        switch self {
        case .openRouter:
            "Sends the whole transcript to OpenRouter to write the notes."
        case .local:
            "Runs a model on this Mac. The transcript never leaves the machine."
        }
    }

    var needsAPIKey: Bool {
        switch self {
        case .openRouter: true
        case .local: false
        }
    }

    /// Builds the client for one generation, reading whatever this provider
    /// needs. `.local` asks the engine to bring its subprocess up first, which
    /// is why this is async and can throw before a request is ever sent.
    @MainActor
    func makeClient(
        settings: Settings,
        engine: LocalLLMEngine
    ) async throws -> any LanguageModelClient {
        switch self {
        case .openRouter:
            return OpenRouterClient(
                apiKey: settings.apiKey(for: .openRouter),
                model: settings.openRouterNotesModel
            )
        case .local:
            return try await engine.client(for: settings.localModel)
        }
    }
}
