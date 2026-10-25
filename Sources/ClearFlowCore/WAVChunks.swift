import Foundation

/// Reads only one request-sized PCM segment at a time, even for long recordings.
public struct WAVChunks {
    public enum Failure: LocalizedError {
        case invalid, tooShort
        public var errorDescription: String? {
            switch self {
            case .invalid: return "The recording is not a complete 16 kHz mono PCM16 WAV file."
            case .tooShort: return "That recording was too short. Speak for at least a moment."
            }
        }
    }
    public let url: URL
    public let count: Int
    public let frames: Int
    private let dataOffset: UInt64
    private let framesPerChunk: Int
    public init(url: URL) throws {
        self.url = url
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        try file.seek(toOffset: 0)
        let header = try file.read(upToCount: 12) ?? Data()
        guard header.count == 12, header.prefix(4) == Data("RIFF".utf8),
              header.suffix(4) == Data("WAVE".utf8), UInt64(header.u32(4)) + 8 == size else { throw Failure.invalid }
        var offset: UInt64 = 12
        var formatSeen = false
        var audio: (UInt64, Int)?
        var chunks = 0
        while offset < size {
            chunks += 1
            guard chunks <= 1024, offset + 8 <= size else { throw Failure.invalid }
            try file.seek(toOffset: offset)
            let chunk = try file.read(upToCount: 8) ?? Data()
            guard chunk.count == 8 else { throw Failure.invalid }
            let length = UInt64(chunk.u32(4))
            let start = offset + 8
            guard start + length + length % 2 <= size else { throw Failure.invalid }
            if chunk.prefix(4) == Data("fmt ".utf8) {
                guard !formatSeen, length >= 16 else { throw Failure.invalid }
                let fmt = try file.read(upToCount: 16) ?? Data()
                guard fmt.count == 16, fmt.u16(0) == 1, fmt.u16(2) == 1,
                      fmt.u32(4) == 16000, fmt.u32(8) == 32000,
                      fmt.u16(12) == 2, fmt.u16(14) == 16 else { throw Failure.invalid }
                formatSeen = true
            } else if chunk.prefix(4) == Data("data".utf8) {
                guard audio == nil, length % 2 == 0 else { throw Failure.invalid }
                audio = (start, Int(length / 2))
            }
            offset = start + length + length % 2
        }
        guard formatSeen, let audio else { throw Failure.invalid }
        guard audio.1 >= 4000 else { throw Failure.tooShort }
        dataOffset = audio.0
        frames = audio.1
        let maxFrames = 240 * 16000
        count = (frames + maxFrames - 1) / maxFrames
        // Balance the segments so a tiny remainder never becomes a rejected <0.25s request.
        framesPerChunk = (frames + count - 1) / count
    }
    public func chunk(at index: Int) throws -> Data {
        guard index >= 0, index < count else { throw Failure.invalid }
        let start = index * framesPerChunk
        let length = min(framesPerChunk, frames - start) * 2
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: dataOffset + UInt64(start * 2))
        let pcm = try file.read(upToCount: length) ?? Data()
        guard pcm.count == length else { throw Failure.invalid }
        var wav = Data("RIFF".utf8)
        wav.appendLE(UInt32(length + 36)); wav.append(Data("WAVEfmt ".utf8))
        wav.appendLE(UInt32(16)); wav.appendLE(UInt16(1)); wav.appendLE(UInt16(1))
        wav.appendLE(UInt32(16000)); wav.appendLE(UInt32(32000))
        wav.appendLE(UInt16(2)); wav.appendLE(UInt16(16))
        wav.append(Data("data".utf8)); wav.appendLE(UInt32(length)); wav.append(pcm)
        return wav
    }
}
private extension Data {
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
