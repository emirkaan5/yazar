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

    /// One line, because that is what the recovery capsule shows. The card's
    /// own buttons carry the next step, so no message repeats "open settings".
    var errorDescription: String? {
        switch self {
        case .credentials: "The provider needs a valid API key."
        case .accessDenied: "This account can't use this model."
        case .paymentRequired: "The provider needs more credit."
        case .rateLimited: "Provider request limit reached."
        case .serviceUnavailable: "The provider is unavailable."
        case .network: "No connection to the provider."
        case .timedOut: "The provider took too long."
        case .invalidResponse: "The provider's reply was unreadable."
        case .invalidModel: "No transcription model is set."
        case .unsupportedLanguage(let language): "No Apple Speech support for \(language)."
        case .unavailable: "Apple Speech isn't available here."
        case .emptyText: "No words were recognized."
        case .unknown: "Transcription couldn't finish."
        case .http(let status): "The provider refused (HTTP \(status))."
        }
    }
}
