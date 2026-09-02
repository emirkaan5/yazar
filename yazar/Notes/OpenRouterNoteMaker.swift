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
            throw NoteMakerError.unreadableReply(Self.preview(of: reply))
        }
        let notes: Notes
        do {
            notes = try Self.decode(json)
        } catch {
            throw NoteMakerError.unreadableReply(Self.preview(of: reply))
        }
        // Every field is optional, so an object with none of the expected keys
        // decodes cleanly into nothing at all. A transcript worth reading does
        // not produce that, and reporting it as "nothing to note" sends the user
        // looking at their meeting rather than at the model. The reply comes with
        // it, because otherwise there is no way to tell afterwards which of the
        // ways this goes wrong actually happened.
        guard !notes.isEmpty else { throw NoteMakerError.noNotes(Self.preview(of: reply)) }
        return notes
    }

    /// Decodes the payload, tolerating the two ways a model nearly follows the
    /// shape it was given: snake_case keys, and wrapping the object in one key of
    /// its own — `{"notes": {…}}`. Only a lone wrapper is unwrapped, so a real
    /// reply carrying a single field is unaffected.
    private static func decode(_ json: Data) throws -> Notes {
        let plain = JSONDecoder()
        let snakeCase = JSONDecoder()
        snakeCase.keyDecodingStrategy = .convertFromSnakeCase

        var bodies = [json]
        if let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
           object.count == 1,
           let inner = object.values.first as? [String: Any],
           let unwrapped = try? JSONSerialization.data(withJSONObject: inner) {
            bodies.append(unwrapped)
        }

        // The richest reading wins rather than the first that is not empty. A
        // reply mixing conventions — "summary" beside "key_points" — decodes
        // under either strategy, and only one of the two carries the lists.
        var best: Notes?
        var failure: (any Error)?
        for body in bodies {
            for decoder in [plain, snakeCase] {
                do {
                    let notes = try decoder.decode(Payload.self, from: body).notes
                    if best.map({ Self.weight(of: notes) > Self.weight(of: $0) }) ?? true {
                        best = notes
                    }
                } catch {
                    failure = failure ?? error
                }
            }
        }
        guard let best else {
            throw failure ?? NoteMakerError.unreadableReply("")
        }
        return best
    }

    /// How much a decoded reading actually carries, used to choose between two
    /// readings of the same reply.
    private static func weight(of notes: Notes) -> Int {
        (notes.summary.isEmpty ? 0 : 1)
            + notes.keyPoints.count
            + notes.decisions.count
            + notes.actionItems.count
    }

    /// The first line or so of what came back, for an error the user reads. Long
    /// enough to recognize a shape, short enough to sit in a label.
    private static func preview(of reply: String) -> String {
        let flattened = reply
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flattened.count > 200 ? flattened.prefix(200) + "…" : flattened
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
    case unreadableReply(String)
    case noNotes(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            "There is no transcript to make notes from."
        case .unreadableReply(let reply):
            "The model's reply was not usable notes. Try another model. It said: \(reply)"
        case .noNotes(let reply):
            "The model replied without any notes. Try another model. It said: \(reply)"
        }
    }
}
