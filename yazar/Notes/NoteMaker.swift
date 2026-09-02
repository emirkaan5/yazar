/// Turns one transcript into structured notes.
///
/// The transcript arrives as plain text because gap markers are inlined when a
/// meeting's segments are assembled, so there is nothing left for a richer type
/// to carry by the time it reaches here.
nonisolated protocol NoteMaker: Sendable {
    /// Implementations must cooperate with task cancellation.
    func makeNotes(from transcript: String) async throws -> Notes
}
