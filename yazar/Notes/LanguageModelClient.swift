/// One turn against a chat-completion model.
///
/// Deliberately smaller than the notes feature that uses it: roadmap item 1
/// cleans up dictations through the same seam, and that returns prose rather
/// than a document. Keeping the client unaware of `Notes` is what lets both
/// share it.
nonisolated protocol LanguageModelClient: Sendable {
    /// Returns the model's reply.
    ///
    /// `expectsJSON` asks the provider to constrain the reply to a single JSON
    /// object. It is a request, not a guarantee — callers still decode
    /// defensively, because a model can ignore the constraint or wrap the object
    /// in a code fence.
    func complete(system: String, user: String, expectsJSON: Bool) async throws -> String
}
