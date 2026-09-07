/// The last useful artifact of one dictation. Recognition replaces audio with
/// text; a delivery failure never sends speech to a provider again.
enum PendingDictation {
    case audio(Recording, rules: Set<FormattingRule>, route: TranscriptionRoute)
    case text(String)
}
