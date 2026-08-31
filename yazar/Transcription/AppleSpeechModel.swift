import Foundation
import Observation
import Speech

/// Install state of Apple Speech's on-device model for the selected language.
/// Transcription downloads the model on first use anyway; this exists so the
/// settings screen can show the wait and start it deliberately, instead of the
/// first dictation stalling behind an unexplained spinner.
@MainActor
@Observable
final class AppleSpeechModel {
    enum State: Equatable {
        case checking
        /// Apple Speech has no model for the requested language at all.
        case unsupported
        case notInstalled
        case downloading
        case installed
        case failed(String)
    }

    private(set) var state: State = .checking
    /// The locale the state describes, once resolved; nil while checking or
    /// when Apple Speech doesn't support the language.
    private(set) var locale: Locale?
    private var task: Task<Void, Never>?

    /// Re-checks the model for `language`, abandoning any check or download
    /// still running for a previous one. Settled after a short pause so typing
    /// in the language field doesn't start a check per keystroke.
    func refresh(language: String?) {
        task?.cancel()
        state = .checking
        locale = nil
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            let resolved = await AppleSpeechTranscriber.supportedLocale(for: language)
            guard !Task.isCancelled, let self else { return }
            guard let resolved else {
                state = .unsupported
                return
            }

            let installed = await AppleSpeechTranscriber.isModelInstalled(for: resolved)
            guard !Task.isCancelled else { return }
            locale = resolved
            state = installed ? .installed : .notInstalled
        }
    }

    func download() {
        guard let locale, state != .downloading else { return }
        task?.cancel()
        state = .downloading
        task = Task { [weak self] in
            do {
                _ = try await AppleSpeechTranscriber.downloadedModule(for: locale)
                guard !Task.isCancelled, let self else { return }
                state = .installed
            } catch {
                guard !Task.isCancelled, let self else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }
}
