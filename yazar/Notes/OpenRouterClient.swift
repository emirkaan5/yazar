import Foundation

/// Chat completions against OpenRouter, using the same credential as
/// transcription.
///
/// `OpenRouterTranscriber` races the request against a sleeping task because a
/// transcription that has not answered in 35 seconds is a dead one. Generation
/// is not like that: a long transcript legitimately takes minutes, so this
/// leans on `timeoutInterval` and cancellation instead of a hard deadline.
nonisolated struct OpenRouterClient: LanguageModelClient {
    let apiKey: String
    let model: String
    var timeout: TimeInterval = 180

    /// Sending no cap is not "no limit": OpenRouter then assumes the model's full
    /// completion ceiling and reserves credit against it, which fails outright on
    /// a key with a spending limit.
    ///
    /// The notes themselves are small, but a reasoning model spends this budget
    /// thinking before it writes anything, and messy real speech needs far more
    /// of that than clean text does. Sized for the thinking, not the answer.
    var maxOutputTokens = 12_000

    func complete(system: String, user: String, expectsJSON: Bool) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterClientError.missingAPIKey
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterClientError.missingModel
        }
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw OpenRouterClientError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let body = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw OpenRouterClientError.service(body.error.detail)
            }
            throw OpenRouterClientError.service("OpenRouter returned HTTP \(httpResponse.statusCode).")
        }

        let body = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let choice = body.choices.first else { throw OpenRouterClientError.emptyReply }

        // A reasoning model answers with `content` null more often than not-at-all:
        // it can spend the whole budget thinking, or refuse. Each of those wants a
        // different sentence, and none of them is "the data is missing".
        let content = choice.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.isEmpty {
            if let refusal = choice.message.refusal, !refusal.isEmpty {
                throw OpenRouterClientError.refused(refusal)
            }
            if choice.finishReason == "length" {
                throw OpenRouterClientError.truncated
            }
            if choice.message.reasoning?.isEmpty == false {
                throw OpenRouterClientError.reasoningOnly
            }
            throw OpenRouterClientError.emptyReply
        }
        // Truncated JSON would otherwise fail brace extraction downstream and be
        // reported as an unusable reply, which points at the wrong cause.
        if choice.finishReason == "length" {
            throw OpenRouterClientError.truncated
        }
        return content
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

    /// The reply's message, whose every interesting field is optional. `content`
    /// is null whenever the model reasoned without answering or refused.
    private struct ResponseMessage: Decodable {
        let content: String?
        let reasoning: String?
        let refusal: String?
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

    private struct ErrorResponse: Decodable {
        let error: ServiceError
    }

    private struct ServiceError: Decodable {
        let message: String
        let metadata: Metadata?

        /// "Provider returned error" is OpenRouter's wrapper around an upstream
        /// failure, and on its own it is a dead end. What actually went wrong is
        /// in the metadata, so fold it into the sentence the user sees.
        var detail: String {
            guard let metadata else { return message }
            let extra = [metadata.providerName, metadata.raw]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            guard !extra.isEmpty else { return message }
            return "\(message) (\(extra.joined(separator: ": ").prefix(300)))"
        }
    }

    /// Each field decoded independently: `raw` is whatever the provider sent and
    /// is not always a string, and a surprise there must not cost us the message
    /// beside it.
    private struct Metadata: Decodable {
        let providerName: String?
        let raw: String?

        enum CodingKeys: String, CodingKey {
            case providerName = "provider_name"
            case raw
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            providerName = try? container.decodeIfPresent(String.self, forKey: .providerName)
            raw = try? container.decodeIfPresent(String.self, forKey: .raw)
        }
    }
}

private enum OpenRouterClientError: LocalizedError {
    case missingAPIKey
    case missingModel
    case invalidEndpoint
    case invalidResponse
    case emptyReply
    case truncated
    case reasoningOnly
    case refused(String)
    case service(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your OpenRouter API key in Yazar Settings."
        case .missingModel: "Choose a notes model in Yazar Settings."
        case .invalidEndpoint: "The OpenRouter chat endpoint is invalid."
        case .invalidResponse: "OpenRouter returned an invalid response."
        case .emptyReply: "OpenRouter returned an empty reply."
        case .truncated:
            "The model ran out of room before finishing the notes. Try a shorter transcript, or a model that reasons less."
        case .reasoningOnly:
            "The model returned its reasoning but no notes. Try again, or choose a different model."
        case .refused(let reason): "The model declined to make notes: \(reason)"
        case .service(let message): message
        }
    }
}
