import Foundation
import Observation

/// Owns one transcript and the notes made from it.
///
/// Shaped after `Yazar`: a state enum the view reads, one cancellable task, and
/// no view-facing wording beyond what a failure already carries.
@MainActor
@Observable
final class NotesComposer {
    enum State: Hashable {
        case idle
        case working
        case failed(String)
    }

    var transcript = "" {
        didSet {
            // Notes on screen belong to the text that produced them, so editing
            // the transcript retires them rather than leaving a stale document
            // beside a changed source.
            guard transcript != oldValue else { return }
            notes = nil
            if case .failed = state { state = .idle }
        }
    }

    private(set) var state: State = .idle
    private(set) var notes: Notes?

    private let settings: Settings
    private var task: Task<Void, Never>?

    init(settings: Settings) {
        self.settings = settings
    }

    var hasTranscript: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canGenerate: Bool {
        state != .working && hasTranscript
    }

    func generate() {
        guard canGenerate else { return }
        let maker = OpenRouterNoteMaker(
            client: OpenRouterClient(
                apiKey: settings.apiKey(for: .openRouter),
                model: settings.openRouterNotesModel
            )
        )
        let transcript = transcript
        notes = nil
        state = .working
        task?.cancel()
        task = Task { [weak self] in
            do {
                let notes = try await maker.makeNotes(from: transcript)
                try Task.checkCancellation()
                self?.notes = notes
                self?.state = .idle
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    /// Reads a dropped or chosen transcript file. Anything that is not decodable
    /// text fails here rather than being sent to the model as mojibake.
    func load(contentsOf url: URL) {
        do {
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            transcript = try String(contentsOf: url, encoding: .utf8)
            state = .idle
        } catch {
            state = .failed("Could not read \(url.lastPathComponent) as text.")
        }
    }
}
