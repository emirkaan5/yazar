import SwiftUI

/// Renders one set of notes. Shared by the import page and the meeting detail so
/// the two cannot drift into showing the same document differently.
struct NotesView: View {
    let notes: Notes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if notes.isEmpty {
                Text("The model found nothing to note in this transcript.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                if !notes.summary.isEmpty {
                    section("Summary") {
                        Text(notes.summary)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !notes.keyPoints.isEmpty {
                    section("Key points") { bullets(notes.keyPoints) }
                }
                if !notes.decisions.isEmpty {
                    section("Decisions") { bullets(notes.decisions) }
                }
                if !notes.actionItems.isEmpty {
                    section("Action items") {
                        bullets(notes.actionItems.map { item in
                            if let owner = item.owner, !owner.isEmpty {
                                "\(owner) — \(item.text)"
                            } else {
                                item.text
                            }
                        })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(items[index])
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
            }
        }
    }
}
