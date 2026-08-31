import Foundation

/// A complete microphone capture in Yazar's canonical 16 kHz mono, signed
/// 16-bit little-endian PCM format.
struct Recording: Sendable {
    static let sampleRate = 16_000

    let pcm16: Data

    var containsSpeech: Bool {
        let sampleCount = pcm16.count / MemoryLayout<Int16>.size
        guard sampleCount >= 4_800 else { return false }

        var sum = 0.0
        pcm16.withUnsafeBytes { bytes in
            for index in 0..<sampleCount {
                let sample = bytes.loadUnaligned(
                    fromByteOffset: index * MemoryLayout<Int16>.size,
                    as: Int16.self
                )
                let normalized = Double(Int16(littleEndian: sample)) / Double(Int16.max)
                sum += normalized * normalized
            }
        }
        return sqrt(sum / Double(sampleCount)) > 0.003
    }

    /// Encodes the canonical samples for providers that accept WAV input.
    var wavData: Data {
        var wav = Data(capacity: 44 + pcm16.count)
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLittleEndian(UInt32(36 + pcm16.count))
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt32(Self.sampleRate))
        wav.appendLittleEndian(UInt32(Self.sampleRate * MemoryLayout<Int16>.size))
        wav.appendLittleEndian(UInt16(MemoryLayout<Int16>.size))
        wav.appendLittleEndian(UInt16(MemoryLayout<Int16>.size * 8))
        wav.append(contentsOf: "data".utf8)
        wav.appendLittleEndian(UInt32(pcm16.count))
        wav.append(pcm16)
        return wav
    }
}

private extension Data {
    mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
