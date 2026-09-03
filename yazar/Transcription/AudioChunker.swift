import Foundation

/// Cuts a stream of canonical PCM into pieces small enough to send one at a time.
///
/// Exists because a whole meeting cannot be one request: `OpenRouterTranscriber`
/// base64-encodes its audio into a JSON body, and an hour of it is a ~153 MB
/// upload under a single timeout. Chunks make each request small, bounded, and
/// individually retryable, and they are what lets a transcript appear while the
/// meeting is still running.
///
/// Boundaries are a plain clock for now, which does cut words in half at every
/// seam. Choosing the quietest moment near the boundary instead is the planned
/// improvement and belongs with the rest of the silence work.
nonisolated struct AudioChunker {
    static let defaultDuration: TimeInterval = 45

    private let chunkBytes: Int
    private var pending = Data()

    init(duration: TimeInterval = defaultDuration) {
        chunkBytes = Int(duration * Double(Recording.sampleRate)) * MemoryLayout<Int16>.size
    }

    /// Takes captured samples and hands back every chunk that is now full.
    /// Usually none or one; more only when a caller arrives with a large backlog.
    mutating func append(_ samples: Data) -> [Data] {
        pending.append(samples)
        var chunks: [Data] = []
        while pending.count >= chunkBytes {
            // Rebased rather than sliced: a Data slice keeps its parent's
            // indices, and everything downstream reads from zero.
            chunks.append(Data(pending.prefix(chunkBytes)))
            pending.removeFirst(chunkBytes)
        }
        return chunks
    }

    /// The remainder, once no more samples are coming. Nil when nothing is left,
    /// so a meeting that ended exactly on a boundary sends no empty request.
    mutating func flush() -> Data? {
        defer { pending = Data() }
        return pending.isEmpty ? nil : pending
    }
}
