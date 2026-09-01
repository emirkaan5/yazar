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
    /// A provider's own words. Service errors are open-ended server prose, so
    /// there is nothing more specific to model here.
    case transcription(String)

    var message: String {
        switch self {
        case .recorder(let error): error.errorDescription ?? "Yazar could not record."
        case .hotKey(let error): error.errorDescription ?? "Yazar could not listen for the dictation key."
        case .clipboardUnavailable: "Couldn't put the transcription on the clipboard."
        case .transcription(let message): message
        }
    }
} 
