/// One thing somebody committed to doing.
///
/// `owner` is read out of what was said — a name spoken aloud in the meeting —
/// not out of speaker attribution, which Yazar does not do. It is optional
/// because most action items are stated without one.
nonisolated struct ActionItem: Codable, Hashable, Sendable {
    let text: String
    let owner: String?
}
