import Foundation

/// Reads canonical meeting audio only when a transcriber asks for more of it.
nonisolated struct MeetingAudio: AsyncSequence, Sendable {
    typealias Element = Data

    /// One second of canonical audio, near enough to the runs `SCStream`
    /// delivers that a provider sees the same shape from a file or from capture.
    static let readSize = Recording.sampleRate * MemoryLayout<Int16>.size

    enum Source: Sendable {
        /// One complete recording. Dictation, which is a meeting that ends
        /// immediately.
        case buffer(Data)
        /// One segment's bytes out of a finished file.
        case range(URL, Range<Int>)
        /// A file still being appended to, from `at` until the writer finishes.
        case tail(URL, at: Int, file: MeetingAudioFile)
    }

    let source: Source

    func makeAsyncIterator() -> Iterator {
        Iterator(source: source)
    }

    struct Iterator: AsyncIteratorProtocol {
        private let source: Source
        private var offset: Int
        private var handle: FileHandle?
        private var returnedBuffer = false

        init(source: Source) {
            self.source = source
            switch source {
            case .buffer:
                offset = 0
            case .range(_, let range):
                offset = range.lowerBound
            case .tail(_, let start, _):
                offset = start
            }
        }

        mutating func next() async throws -> Data? {
            do {
                try Task.checkCancellation()
                switch source {
                case .buffer(let data):
                    guard !returnedBuffer, !data.isEmpty else { return nil }
                    returnedBuffer = true
                    return data

                case .range(let url, let range):
                    guard offset < range.upperBound else {
                        close()
                        return nil
                    }
                    let handle = try open(url)
                    guard let data = try handle.read(
                        upToCount: Swift.min(MeetingAudio.readSize, range.upperBound - offset)
                    ), !data.isEmpty else {
                        close()
                        return nil
                    }
                    offset += data.count
                    return data

                case .tail(let url, _, let file):
                    while true {
                        // The flag is read first on purpose. A byte count read
                        // first can be stale by the time the flag says nothing
                        // more is coming, which would end the read with the
                        // last buffer of the meeting still unread.
                        let finished = file.isFinished
                        if offset < file.availableBytes { break }
                        if finished {
                            close()
                            return nil
                        }
                        try await Task.sleep(for: .milliseconds(200))
                    }
                    let handle = try open(url)
                    guard let data = try handle.read(
                        upToCount: Swift.min(MeetingAudio.readSize, file.availableBytes - offset)
                    ), !data.isEmpty else {
                        close()
                        return nil
                    }
                    offset += data.count
                    return data
                }
            } catch {
                close()
                throw error
            }
        }

        private mutating func open(_ url: URL) throws -> FileHandle {
            if let handle { return handle }
            let opened = try FileHandle(forReadingFrom: url)
            do {
                try opened.seek(toOffset: UInt64(offset))
            } catch {
                try? opened.close()
                throw error
            }
            handle = opened
            return opened
        }

        private mutating func close() {
            try? handle?.close()
            handle = nil
        }
    }
}
