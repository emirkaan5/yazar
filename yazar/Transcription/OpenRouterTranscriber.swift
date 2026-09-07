import Foundation

nonisolated struct OpenRouterTranscriber: Transcriber {
    /// A literal the app ships with: a parse failure here is a typo in this
    /// file, not something a provider or a user can cause.
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!

    /// A dictation is a few seconds of audio and the user is waiting on it, so
    /// the whole thing gets one short deadline.
    private static let dictationTimeout = Duration.seconds(35)
    /// A meeting chunk is longer audio on an unknown uplink, and it is one of
    /// many. The deadline is per chunk rather than per meeting: one slow upload
    /// must not take an hour of transcription with it.
    private static let chunkTimeout = Duration.seconds(120)

    let apiKey: String
    let model: String
    let language: String?

    func transcribe(_ recording: Recording) async throws -> String {
        try await withTimeout(Self.dictationTimeout) {
            try await performRequest(recording.wavData)
        }
    }

    /// Transcribes a meeting as it is captured, one chunk of audio per request.
    ///
    /// Sequential on purpose. Parallel uploads would return out of order and the
    /// transcript is being appended to as it arrives, so ordering is the whole
    /// contract. Chunk boundaries also lose the context either side of them,
    /// which is the price of not waiting until the meeting ends to see anything.
    func transcribe(_ audio: MeetingAudio) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                var chunker = AudioChunker()
                do {
                    for try await samples in audio {
                        for chunk in chunker.append(samples) {
                            try await send(chunk, to: continuation)
                        }
                    }
                    if let last = chunker.flush() {
                        try await send(last, to: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private func send(
        _ chunk: Data,
        to continuation: AsyncThrowingStream<TranscriptUpdate, any Error>.Continuation
    ) async throws {
        let recording = Recording(pcm16: chunk)
        // A silent chunk is a request that costs money and comes back as a
        // hallucinated pleasantry, so it is never sent. Nobody spoke; the
        // transcript says nothing.
        guard recording.containsSpeech else { return }
        let text = try await withTimeout(Self.chunkTimeout) {
            try await performRequest(recording.wavData)
        }
        guard !text.isEmpty else { return }
        // Nothing here is provisional: a chunk comes back finished or not at all.
        continuation.yield(TranscriptUpdate(finalized: text + " "))
    }

    /// Bounds one request. `URLRequest.timeoutInterval` covers the network alone,
    /// which is not the same as the wait the caller sees.
    private func withTimeout<Value: Sendable>(
        _ duration: Duration,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TranscriptionFailure.timedOut
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                preconditionFailure("The timeout group always has two child tasks")
            }
            return value
        }
    }

    private func performRequest(_ wav: Data) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionFailure.credentials
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptionFailure.invalidModel
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model,
            inputAudio: .init(data: wav.base64EncodedString(), format: "wav"),
            language: Self.isoCode(for: language)
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TranscriptionFailure.invalidResponse
        }
        return try Self.decodeResponse(data, statusCode: response.statusCode)
    }

    /// Returns trimmed transcript text or throws a provider-neutral failure.
    /// A documented OpenRouter error envelope is classified from its structured
    /// fields; remote message prose and response bodies are never retained or
    /// surfaced, because they can echo the audio that was sent.
    ///
    /// Not private so the wire contract can be tested without a live request.
    static func decodeResponse(_ data: Data, statusCode: Int) throws -> String {
        guard (200..<300).contains(statusCode) else {
            throw TranscriptionFailure.httpStatus(statusCode)
        }
        let decoder = JSONDecoder()
        if let body = try? decoder.decode(ResponseBody.self, from: data) {
            return body.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Work that fails after the response has started still arrives as 200
        // carrying only an error object, so a 2xx body is not proof of success.
        guard let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) else {
            throw TranscriptionFailure.invalidResponse
        }
        throw envelope.failure
    }

    /// Whisper-style endpoints expect a bare ISO-639-1 code, but the language
    /// setting is shared with Apple Speech, which wants BCP-47. Sending the
    /// primary subtag means a value like "en-US" still selects English instead of
    /// being silently ignored.
    private static func isoCode(for language: String?) -> String? {
        guard let language else { return nil }
        return Locale(identifier: language).language.languageCode?.identifier ?? language
    }

    private struct RequestBody: Encodable {
        let model: String
        let inputAudio: InputAudio
        let language: String?

        enum CodingKeys: String, CodingKey {
            case model
            case inputAudio = "input_audio"
            case language
        }
    }

    private struct InputAudio: Encodable {
        let data: String
        let format: String
    }

    private struct ResponseBody: Decodable {
        let text: String
    }

    /// OpenRouter's documented error envelope. `message` is deliberately absent:
    /// it is remote prose that can quote the request.
    private struct ErrorEnvelope: Decodable {
        let error: ServiceError

        struct ServiceError: Decodable {
            let code: Int
            let metadata: Metadata?
        }

        struct Metadata: Decodable {
            let errorType: String?

            enum CodingKeys: String, CodingKey {
                case errorType = "error_type"
            }
        }

        /// A stable `error_type` wins where it names exactly one cause, because
        /// it survives the numeric code being 200. Anything else — an unmapped
        /// type, an image or length error dictation cannot produce — falls back
        /// to reading the code as an HTTP status.
        var failure: TranscriptionFailure {
            switch error.metadata?.errorType {
            case "authentication": .credentials
            case "permission_denied": .accessDenied
            case "payment_required": .paymentRequired
            case "rate_limit_exceeded": .rateLimited
            case "provider_overloaded", "provider_unavailable", "server": .serviceUnavailable
            case "timeout": .timedOut
            default: .httpStatus(error.code)
            }
        }
    }

}
