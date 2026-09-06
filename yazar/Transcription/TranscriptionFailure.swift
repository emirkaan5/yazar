import Foundation

/// Stable recovery causes at the provider boundary. Remote prose and response
/// bodies are deliberately excluded: they can echo private request contents.
nonisolated enum TranscriptionFailure: Error, LocalizedError, Hashable, Sendable {
    case credentials
    case accessDenied
    case paymentRequired
    case rateLimited
    case serviceUnavailable
    case network
    case timedOut
    case invalidResponse
    case invalidModel
    case unsupportedLanguage(String)
    case unavailable
    case emptyText
    case unknown
    case http(Int)

    init(_ error: any Error) {
        if let failure = error as? Self {
            self = failure
        } else if let error = error as? URLError {
            self = error.code == .timedOut ? .timedOut : .network
        } else {
            self = .unknown
        }
    }

    static func httpStatus(_ status: Int) -> Self {
        switch status {
        case 401: .credentials
        case 402: .paymentRequired
        case 403: .accessDenied
        case 429: .rateLimited
        case 500...599: .serviceUnavailable
        default: .http(status)
        }
    }

    var errorDescription: String? {
        switch self {
        case .credentials: "The provider needs a valid API key."
        case .accessDenied: "This account cannot access the selected model."
        case .paymentRequired: "The provider requires payment. Check your credits."
        case .rateLimited: "Provider request limit reached."
        case .serviceUnavailable: "The provider is temporarily unavailable."
        case .network: "Couldn't connect to the provider. Check your connection."
        case .timedOut: "The provider took too long to respond."
        case .invalidResponse: "The provider returned a response Yazar couldn't use."
        case .invalidModel: "Choose a transcription model in Transcription settings."
        case .unsupportedLanguage(let language): "Apple Speech doesn't support \(language)."
        case .unavailable: "Apple Speech isn't available on this Mac."
        case .emptyText: "No words were recognized."
        case .unknown: "Transcription couldn't finish."
        case .http(let status): "The provider rejected the request (HTTP \(status))."
        }
    }
}
