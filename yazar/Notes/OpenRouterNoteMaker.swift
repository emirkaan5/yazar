import Foundation

/// Builds the notes prompt, sends it through a `LanguageModelClient`, and
/// decodes the reply.
///
/// It holds a client rather than being one, so the prompt is the only thing
/// here that is about notes, and the transport stays reusable.
nonisolated struct OpenRouterNoteMaker: NoteMaker {
    let client: any LanguageModelClient

    func makeNotes(from transcript: String) async throws -> Notes {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NoteMakerError.emptyTranscript }

        let reply = try await client.complete(
            system: Self.systemPrompt,
            user: trimmed,
            expectsJSON: true
        )
        try Task.checkCancellation()

        guard let json = Self.jsonObject(in: reply) else {
            throw NoteMakerError.unreadableReply
        }
        do {
            return try JSONDecoder().decode(Payload.self, from: json).notes
        } catch {
            throw NoteMakerError.unreadableReply
        }
    }

    // Rules earn their place by naming a specific way these notes go wrong:
    // invented continuity across a gap, confident nonsense built on a misheard
    // word, and padding empty sections to look thorough.
    private static let systemPrompt = """
        You turn a meeting transcript into structured notes.

        Rules:
        - Use only what the transcript says. Never infer a decision, an owner, or \
        an outcome that was not stated. If something important was left unresolved, \
        say that rather than resolving it.
        - The transcript is machine-transcribed and will contain errors, misheard \
        names, and missing punctuation. Read through them, but do not build a claim \
        on a word that looks garbled.
        - A marker like [resumed after 4h] means recording deliberately stopped and \
        later restarted. Treat what follows as a separate stretch of conversation. \
        Never describe the two sides of that marker as one continuous exchange.
        - A marker like [recording interrupted, up to 6 minutes not captured] means \
        speech is missing from the transcript entirely. Do not bridge the hole, and \
        do not assume what follows continues what came before.
        - The person reading these notes may not be a speaker in the transcript. \
        Do not address them as a participant or attribute anything to them.
        - Prefer fewer, real entries to more, padded ones. Empty arrays are correct \
        when nothing qualifies.
        - Write plainly, in the past tense, without meeting-summary filler.

        Reply with a single JSON object and nothing else:
        {
          "summary": "two to four sentences on what the meeting was about and where it landed",
          "keyPoints": ["substantive points raised, one per entry"],
          "decisions": ["decisions actually settled, one per entry"],
          "actionItems": [{"text": "what is to be done", "owner": "name if one was said, otherwise null"}]
        }
        """

    /// Models wrap JSON in code fences or add a sentence before it even when
    /// asked not to. Taking the outermost braces tolerates both without a
    /// fence-stripping special case.
    private static func jsonObject(in reply: String) -> Data? {
        guard let start = reply.firstIndex(of: "{"),
              let end = reply.lastIndex(of: "}"),
              start < end else { return nil }
        return Data(reply[start...end].utf8)
    }

    /// Every field optional, because a model that finds no decisions is as
    /// likely to omit the key as to send an empty array, and neither is an error.
    private struct Payload: Decodable {
        let summary: String?
        let keyPoints: [String]?
        let decisions: [String]?
        let actionItems: [Item]?

        var notes: Notes {
            Notes(
                summary: summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                keyPoints: (keyPoints ?? []).filter { !$0.isEmpty },
                decisions: (decisions ?? []).filter { !$0.isEmpty },
                actionItems: (actionItems ?? [])
                    .filter { !$0.text.isEmpty }
                    .map { ActionItem(text: $0.text, owner: $0.owner) }
            )
        }
    }

    private struct Item: Decodable {
        let text: String
        let owner: String?
    }
}

enum NoteMakerError: LocalizedError {
    case emptyTranscript
    case unreadableReply

    var errorDescription: String? {
        switch self {
        case .emptyTranscript: "There is no transcript to make notes from."
        case .unreadableReply: "The model's reply was not usable notes. Try again, or try another model."
        }
    }
}
