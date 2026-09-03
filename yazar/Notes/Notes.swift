/// Structured notes derived from one transcript.
///
/// This shape is the contract between whatever produced the notes and whatever
/// displays them, so a second provider can be added later without a view
/// learning where its notes came from.
nonisolated struct Notes: Codable, Hashable, Sendable {
    let summary: String
    let keyPoints: [String]
    let decisions: [String]
    let actionItems: [ActionItem]

    var isEmpty: Bool {
        summary.isEmpty && keyPoints.isEmpty && decisions.isEmpty && actionItems.isEmpty
    }

    /// Markdown for copying out. Until meetings are stored, this is the only way
    /// a result leaves Yazar, so empty sections are dropped rather than written
    /// as bare headings.
    var markdown: String {
        var sections: [String] = []

        if !summary.isEmpty {
            sections.append("## Summary\n\n\(summary)")
        }
        if !keyPoints.isEmpty {
            sections.append("## Key points\n\n" + keyPoints.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !decisions.isEmpty {
            sections.append("## Decisions\n\n" + decisions.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !actionItems.isEmpty {
            let items = actionItems.map { item in
                if let owner = item.owner, !owner.isEmpty {
                    "- **\(owner)** — \(item.text)"
                } else {
                    "- \(item.text)"
                }
            }
            sections.append("## Action items\n\n" + items.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}
