import Foundation

/// Chat completions against a local `mlx_lm.server` over loopback.
///
/// The request body is the same OpenAI shape `OpenRouterClient` sends, but the
/// response handling is deliberately its own: OpenRouter's reply decoder has
/// grown a pile of provider-specific cases — `reasoning`, `refusal`, metadata
/// wrappers, HTTP 200 carrying an error object — that a server running on this
/// Mac does not produce. Sharing that code would mean carrying its quirks here
/// for no reason.
nonisolated struct LocalLLMClient: LanguageModelClient {
    /// The server's `/v1` origin, e.g. `http://127.0.0.1:52831`.
    let baseURL: URL
    let model: String

    /// Generous on purpose. On-device generation is slower than a hosted API,
    /// and the very first request after a model changes also pays for loading
    /// several gigabytes of weights into memory.
    var timeout: TimeInterval = 600

    /// mlx_lm defaults to a small completion budget; notes plus a reasoning
    /// model's scratch work need more room than that.
    var maxOutputTokens = 12_000

    func complete(system: String, user: String, expectsJSON: Bool) async throws -> String {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalLLMClientError.missingModel
        }
        let url = baseURL.appending(path: "v1/chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: system),
                Message(role: "user", content: user),
            ],
            maxTokens: maxOutputTokens,
            responseFormat: expectsJSON ? ResponseFormat(type: "json_object") : nil
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost
            || error.code == .networkConnectionLost {
            throw LocalLLMClientError.serverUnreachable
        }
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalLLMClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocalLLMClientError.service(Self.message(from: data, status: httpResponse.statusCode))
        }

        let body: ResponseBody
        do {
            body = try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw LocalLLMClientError.unreadableResponse(Self.preview(of: data))
        }
        guard let choice = body.choices.first else { throw LocalLLMClientError.emptyReply }

        let content = choice.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if choice.finishReason == "length", content.isEmpty {
            throw LocalLLMClientError.truncated
        }
        guard !content.isEmpty else { throw LocalLLMClientError.emptyReply }
        if choice.finishReason == "length" {
            throw LocalLLMClientError.truncated
        }
        return content
    }

    /// mlx_lm reports errors as `{"detail": "..."}` (FastAPI's default) or as a
    /// bare string. Either way the first line of it is what identifies the
    /// problem.
    private static func message(from data: Data, status: Int) -> String {
        if let detail = try? JSONDecoder().decode(ErrorBody.self, from: data), !detail.detail.isEmpty {
            return detail.detail
        }
        let preview = Self.preview(of: data)
        return preview.isEmpty ? "The local model server returned HTTP \(status)." : preview
    }

    private static func preview(of data: Data) -> String {
        let text = String(decoding: data.prefix(2_000), as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return text.count > 200 ? text.prefix(200) + "…" : text
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let maxTokens: Int
        let responseFormat: ResponseFormat?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case maxTokens = "max_tokens"
            case responseFormat = "response_format"
        }
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct ResponseFormat: Encodable {
        let type: String
    }

    private struct ResponseBody: Decodable {
        let choices: [Choice]
    }

    private struct Choice: Decodable {
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    private struct ResponseMessage: Decodable {
        let content: String?
    }

    private struct ErrorBody: Decodable {
        let detail: String
    }
}

enum LocalLLMClientError: LocalizedError {
    case missingModel
    case serverUnreachable
    case invalidResponse
    case emptyReply
    case truncated
    case unreadableResponse(String)
    case service(String)

    var errorDescription: String? {
        switch self {
        case .missingModel:
            "Choose a local model in Settings › Local Models."
        case .serverUnreachable:
            "The local model server stopped responding. Try again."
        case .invalidResponse:
            "The local model server returned an invalid response."
        case .emptyReply:
            "The local model returned an empty reply. Try again, or choose a different model."
        case .truncated:
            "The model ran out of room before finishing the notes. Try a shorter transcript, or a model that reasons less."
        case .unreadableResponse(let body):
            "The local model server's reply was not in the expected shape. It sent: \(body)"
        case .service(let message):
            message
        }
    }
}
