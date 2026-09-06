import Foundation
@testable import yazar

/// A provider whose replies can arrive after cancellation, like an external
/// request that has already completed on the server.
actor DictationTestTranscriber: Transcriber {
    private(set) var recordings: [Recording] = []
    private var replies: [Int: CheckedContinuation<String, any Error>] = [:]

    func transcribe(_ recording: Recording) async throws -> String {
        let index = recordings.count
        recordings.append(recording)
        return try await withCheckedThrowingContinuation { replies[index] = $0 }
    }

    func reply(_ index: Int, with result: Result<String, TranscriptionFailure>) {
        switch result {
        case .success(let text): replies.removeValue(forKey: index)?.resume(returning: text)
        case .failure(let error): replies.removeValue(forKey: index)?.resume(throwing: error)
        }
    }

    nonisolated func transcribe(_ audio: MeetingAudio) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
