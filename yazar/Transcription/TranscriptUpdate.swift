/// One step of a streaming transcription.
///
/// Split in two because the parts are consumed differently: finalized text is
/// appended and never revisited, while the volatile tail is the provider's
/// current guess at what is still being said and is replaced wholesale by the
/// next update. Merging them would leave the caller unable to tell which of the
/// two it just received.
nonisolated struct TranscriptUpdate: Hashable, Sendable {
    /// Text the provider has committed to, ready to be appended.
    var finalized: String = ""
    /// The unstable tail, which supersedes the previous one. Empty when the
    /// provider has just finalized and has nothing in flight.
    var volatile: String = ""
}
