import Foundation

/// Applies the user's formatting rules to a transcript.
///
/// Runs before `TranscriptFitter`, which reconciles the result with the text
/// around the caret. Nothing may run after the fitter, so every rewrite that
/// depends only on the user's configuration belongs here.
nonisolated enum TranscriptFormatter {
    /// An empty rule set returns the transcript unchanged, so callers never have
    /// to branch on whether formatting is configured.
    static func apply(_ rules: Set<FormattingRule>, to transcript: String) -> String {
        var output = transcript
        // Driven by `allCases` rather than by `rules` so the order two rules
        // compose in is the declaration order, not Set iteration order.
        for rule in FormattingRule.allCases where rules.contains(rule) {
            switch rule {
            case .lowercase:
                output = output.lowercased()
            }
        }
        return output
    }
}
