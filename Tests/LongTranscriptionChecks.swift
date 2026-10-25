import Foundation
import ClearFlowCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}
func wav(frames: Int, metadata: Bool = false) -> Data {
    var data = Data("RIFF".utf8)
    appendLE(UInt32(frames * 2 + 36 + (metadata ? 12 : 0)), to: &data)
    data.append(Data("WAVE".utf8))
    if metadata { data.append(Data("JUNK".utf8)); appendLE(UInt32(3), to: &data); data.append(contentsOf: [1, 2, 3, 0]) }
    data.append(Data("fmt ".utf8)); appendLE(UInt32(16), to: &data)
    appendLE(UInt16(1), to: &data); appendLE(UInt16(1), to: &data)
    appendLE(UInt32(16000), to: &data); appendLE(UInt32(32000), to: &data)
    appendLE(UInt16(2), to: &data); appendLE(UInt16(16), to: &data)
    data.append(Data("data".utf8)); appendLE(UInt32(frames * 2), to: &data)
    // Varied samples make dropped/reordered bytes visible across boundaries.
    data.append(contentsOf: (0..<(frames * 2)).map { UInt8($0 % 251) })
    return data
}
final class StubService: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                                 httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
func payload(_ request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 65536)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }; data.append(contentsOf: buffer.prefix(n))
        }
    }
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}
@main enum LongTranscriptionChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("long.wav")
        let original = wav(frames: 601 * 16000, metadata: true)
        try original.write(to: file)
        let chunks = try WAVChunks(url: file)
        require(chunks.count == 3, "601 seconds must be split into three safe requests")
        var pcm = Data()
        for i in 0..<chunks.count {
            let data = try chunks.chunk(at: i)
            require(data.count <= 240 * 32000 + 44, "Each request stays below backend duration/size limits")
            pcm.append(data.dropFirst(44))
        }
        require(pcm == original.dropFirst(56), "Every sample is preserved exactly once and in order")
        let edge = directory.appendingPathComponent("edge.wav")
        try wav(frames: 240 * 16000 + 1).write(to: edge)
        let balanced = try WAVChunks(url: edge)
        require(balanced.count == 2, "Long input must split")
        let lastChunk = try balanced.chunk(at: 1)
        require(lastChunk.count >= 8044, "A tiny final remainder must not create an invalid request")
        let bad = directory.appendingPathComponent("bad.wav")
        try original.dropLast().write(to: bad)
        do { _ = try WAVChunks(url: bad); fatalError("Truncated WAV was accepted") } catch WAVChunks.Failure.invalid {}
        try wav(frames: 3999).write(to: bad)
        do { _ = try WAVChunks(url: bad); fatalError("Short WAV was accepted") } catch WAVChunks.Failure.tooShort {}

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubService.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var calls = 0
        var ids = Set<String>()
        StubService.handler = { request in
            let body = try payload(request)
            let id = body["requestId"] as! String
            require(ids.insert(id).inserted, "Segments need distinct IDs")
            let audio = Data(base64Encoded: body["audio"] as! String)!
            require(audio.count <= 240 * 32000 + 44, "Client sent an oversized request")
            require(request.url?.host == "localhost", "Never switch endpoints")
            calls += 1
            if calls == 2 { return (422, Data("{\"error\":{\"code\":\"NO_SPEECH\",\"message\":\"Silence\"}}".utf8)) }
            return (200, try JSONSerialization.data(withJSONObject: ["text": "Part \(calls).", "requestId": id, "model": "fixture", "durationMs": 1]))
        }
        let id = UUID()
        let result = try await TranscriptionClient.transcribe(file: file, id: id, endpoint: "http://localhost:8768", token: "fixture-token", language: "en", vocabulary: "", session: session)
        require(result.text == "Part 1. Part 3." && result.requestId == id.uuidString && calls == 3, "Combine ordered speech and skip only silent segments")

        calls = 0
        StubService.handler = { request in
            calls += 1
            let id = try payload(request)["requestId"] as! String
            if calls == 2 { return (500, Data("{\"error\":{\"code\":\"FAILED\",\"message\":\"Failure\"}}".utf8)) }
            return (200, try JSONSerialization.data(withJSONObject: ["text": "First", "requestId": id, "model": "fixture", "durationMs": 1]))
        }
        do {
            _ = try await TranscriptionClient.transcribe(file: file, id: UUID(), endpoint: "http://localhost:8768", token: "fixture-token", language: "en", vocabulary: "", session: session)
            fatalError("Failed segment must not return partial text as a completed result")
        } catch let error as TranscriptionServiceError { require(error.status == 500 && calls == 2, "Stop after a failed segment") }

        calls = 0
        let task = Task {
            try await TranscriptionClient.transcribe(file: file, id: UUID(), endpoint: "http://localhost:8768", token: "fixture-token", language: "en", vocabulary: "", session: session,
                progress: { _, _ in withUnsafeCurrentTask { $0?.cancel() } })
        }
        do { _ = try await task.value; fatalError("Cancellation must not return a transcript") } catch is CancellationError {}
        require(calls == 0, "Cancellation stops requests before upload")
        let between = Task {
            try await TranscriptionClient.transcribe(file: file, id: UUID(), endpoint: "http://localhost:8768", token: "fixture-token", language: "en", vocabulary: "", session: session,
                progress: { part, _ in if part == 2 { withUnsafeCurrentTask { $0?.cancel() } } })
        }
        do { _ = try await between.value; fatalError("Cancellation between segments must not deliver partial text") } catch is CancellationError {}
        require(calls == 1, "No second upload after cancellation")
        print("PASS: 601-second WAV segmentation, exact sample coverage, short remainder, invalid files, ordered aggregation, silent segment, failure and cancellation")
    }
}
