import Foundation

/// Append-only store for one meeting's audio, in Yazar's canonical 16 kHz mono
/// signed 16-bit PCM.
///
/// Raw samples, deliberately, with no container. Resuming a meeting is then a
/// plain append rather than a header rewrite, and a file cut off by a crash is a
/// shorter recording rather than a corrupt one. WAV framing stays a
/// transcription- and export-time concern, where `Recording.wavData` already
/// builds it on demand.
nonisolated final class MeetingAudioFile {
    let url: URL
    private let handle: FileHandle

    init(url: URL) throws {
        self.url = url
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    /// The handle sits at the end after opening and after every write, so its
    /// offset is the length without a stat call.
    var byteCount: UInt64 {
        (try? handle.offset()) ?? 0
    }

    /// Seconds of audio written so far, derived from the file's size because raw
    /// PCM at a fixed rate has no other length to disagree with.
    var duration: TimeInterval {
        Double(byteCount) / Double(Recording.sampleRate * MemoryLayout<Int16>.size)
    }

    func append(_ samples: Data) throws {
        guard !samples.isEmpty else { return }
        try handle.write(contentsOf: samples)
    }

    /// Flushes to disk. Called at segment boundaries so a crash costs at most
    /// the samples since the last one, not the meeting.
    func synchronize() {
        try? handle.synchronize()
    }

    func close() {
        try? handle.synchronize()
        try? handle.close()
    }
}
