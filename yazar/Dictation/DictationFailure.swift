import Foundation

/// Why a dictation ended badly.
///
/// The state machine carries this rather than a rendered sentence, so the
/// wording is derived where it is shown and the overlay can eventually tell
/// these apart — a missing API key wants a different offer than a dead
/// microphone. Cases wrap the errors their subsystems already define instead of
/// restating them, so there is one description per failure.
enum DictationFailure: Hashable {
    case recorder(RecorderError)
    case hotKey(HotKeyError)
    case clipboardUnavailable
    case transcription(TranscriptionFailure)

    var settingsPage: AppPage? {
        switch self {
        case .hotKey: .systemAccess
        case .recorder: .general
        case .clipboardUnavailable: nil
        case .transcription(let failure):
            switch failure {
            case .credentials, .accessDenied, .paymentRequired, .rateLimited: .providers
            default: .transcription
            }
        }
    }

    /// Wrapped errors describe themselves. Only the clipboard failure is the
    /// dictation layer's own, so it is the only sentence written here.
    var message: String {
        switch self {
        case .recorder(let error): error.localizedDescription
        case .hotKey(let error): error.localizedDescription
        case .clipboardUnavailable: "Couldn't write to the clipboard."
        case .transcription(let failure): failure.localizedDescription
        }
    }
}
