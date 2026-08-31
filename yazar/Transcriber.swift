/// Transcribes one complete recording with a selected speech-to-text provider.
protocol Transcriber: Sendable {
    /// Returns finalized, trimmed text. An empty string means the provider
    /// recognized no text. Implementations must cooperate with task cancellation.
    func transcribe(_ recording: Recording, language: String?) async throws -> String
}
