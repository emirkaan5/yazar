import Foundation

/// Transcribes speech with a selected speech-to-text provider.
nonisolated protocol Transcriber: Sendable {
    /// Returns finalized, trimmed text for one complete recording. An empty
    /// string means the provider recognized no text. Implementations must
    /// cooperate with task cancellation.
    func transcribe(_ recording: Recording, language: String?) async throws -> String

    /// Transcribes audio that is still being captured.
    ///
    /// The entry point meetings use: `audio` carries canonical PCM as it arrives
    /// and is finished by the recorder, and updates come back while the meeting
    /// is still running rather than in one lump at the end. Ending the returned
    /// stream, or cancelling the consuming task, abandons the transcription.
    func transcribe(
        _ audio: AsyncStream<Data>,
        language: String?
    ) -> AsyncThrowingStream<TranscriptUpdate, any Error>
}
