import Foundation

/// A local model offered in Settings › Local Models. `summary` is the one line
/// under the model id in the picker, so it stays short: rough download size and
/// who it is for.
///
/// Every id is an `mlx-community` repo, which is what `mlx_lm.server` pulls from
/// Hugging Face on first use.
struct SuggestedLocalModel: Identifiable {
    let id: String
    let summary: String

    /// What a fresh install writes into `Settings.localModel`.
    static let defaultID = "mlx-community/gemma-3-12b-it-4bit"

    static let all: [SuggestedLocalModel] = [
        SuggestedLocalModel(
            id: "mlx-community/gemma-3-12b-it-4bit",
            summary: "Best notes. ~7 GB download, needs ~12 GB free memory"
        ),
        SuggestedLocalModel(
            id: "mlx-community/Qwen3-8B-4bit",
            summary: "Strong and lighter. ~4.5 GB"
        ),
        SuggestedLocalModel(
            id: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            summary: "Fastest and smallest. ~2.5 GB"
        ),
    ]
}
