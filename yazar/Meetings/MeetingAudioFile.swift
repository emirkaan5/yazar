import Foundation
import Synchronization

/// Append-only store for one meeting's audio, in Yazar's canonical 16 kHz mono
/// signed 16-bit PCM.
///
/// Raw samples, deliberately, with no container. Resuming a meeting is then a
/// plain append rather than a header rewrite, and a file cut off by a crash is a
/// shorter recording rather than a corrupt one. WAV framing stays a
/// transcription- and export-time concern, where `Recording.wavData` already
/// builds it on demand.
/// The handle stays on the capture queue during recording. `written` and
/// `finished` are the only state readers touch across threads.
nonisolated final class MeetingAudioFile: @unchecked Sendable {
    let url: URL
    private let handle: FileHandle
    private let written: Atomic<Int>
    private let finished = Atomic(false)

    init(url: URL) throws {
        self.url = url
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        let size = try handle.seekToEnd()
        self.handle = handle
        written = Atomic(Int(size))
    }

    /// Published after each successful write, so readers never run ahead of the
    /// file and nobody else needs to touch the writer's handle.
    var byteCount: UInt64 {
        UInt64(availableBytes)
    }

    var availableBytes: Int {
        written.load(ordering: .acquiring)
    }

    var isFinished: Bool {
        finished.load(ordering: .acquiring)
    }

    /// Seconds of audio written so far, derived from the file's size because raw
    /// PCM at a fixed rate has no other length to disagree with.
    var duration: TimeInterval {
        Self.duration(forByteCount: availableBytes)
    }

    static func duration(forByteCount byteCount: Int) -> TimeInterval {
        Double(byteCount) / Double(Recording.sampleRate * MemoryLayout<Int16>.size)
    }

    func append(_ samples: Data) throws {
        guard !samples.isEmpty else { return }
        try handle.write(contentsOf: samples)
        written.store(availableBytes + samples.count, ordering: .releasing)
    }

    /// Flushes to disk. Called at segment boundaries so a crash costs at most
    /// the samples since the last one, not the meeting.
    func synchronize() {
        try? handle.synchronize()
    }

    func close() {
        try? handle.synchronize()
        try? handle.close()
        finished.store(true, ordering: .releasing)
    }
}
