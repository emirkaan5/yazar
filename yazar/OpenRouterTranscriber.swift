import Foundation

nonisolated struct OpenRouterTranscriber: Transcriber {
    let apiKey: String
    let model: String

    func transcribe(_ recording: Recording, language: String?) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await performRequest(recording.wavData, language: language) }
            group.addTask {
                try await Task.sleep(for: .seconds(35))
                throw OpenRouterTranscriberError.timedOut
            }
            defer { group.cancelAll() }
            guard let text = try await group.next() else {
                throw OpenRouterTranscriberError.invalidResponse
            }
            return text
        }
    }

    private func performRequest(_ wav: Data, language: String?) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterTranscriberError.missingAPIKey
        }
        guard let url = URL(string: "https://openrouter.ai/api/v1/audio/transcriptions") else {
            throw OpenRouterTranscriberError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model,
            inputAudio: .init(data: wav.base64EncodedString(), format: "wav"),
            language: language
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterTranscriberError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw OpenRouterTranscriberError.service(response.error.message)
            }
            throw OpenRouterTranscriberError.service(
                "OpenRouter returned HTTP \(httpResponse.statusCode)."
            )
        }

        let responseBody = try JSONDecoder().decode(ResponseBody.self, from: data)
        return responseBody.text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private struct ErrorResponse: Decodable {
        let error: ServiceError
    }

    private struct ServiceError: Decodable {
        let message: String
    }
}

private enum OpenRouterTranscriberError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case timedOut
    case service(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your OpenRouter API key in Yazar Settings."
        case .invalidEndpoint: "The OpenRouter transcription endpoint is invalid."
        case .invalidResponse: "OpenRouter returned an invalid response."
        case .timedOut: "OpenRouter transcription timed out."
        case .service(let message): message
        }
    }
}
