import Foundation
import ClearFlowCore

struct TranscriptionReply: Decodable {
    let text: String
    let requestId: String
    let model: String
    let durationMs: Double
}
struct TranscriptionPayload: Encodable {
    let audio: String
    let language: String?
    let vocabulary: String?
    let requestId: String
}
struct ErrorEnvelope: Decodable {
    struct Detail: Decodable { let code: String; let message: String }
    let error: Detail
}

struct TranscriptionServiceError: LocalizedError {
    let status: Int
    let code: String
    let message: String
    var errorDescription: String? { message }
}

enum TranscriptionClient {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 120
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": "ClearFlow/0.1"]
        return URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
    }()
    static func transcribe(audio: Data, id: UUID, endpoint: String, token: String,
                           language: String, vocabulary: String, session: URLSession = session) async throws -> TranscriptionReply {
        guard let base = Endpoint.validated(endpoint), !token.isEmpty else {
            throw AppError.message("Set your service address and access token in Settings.")
        }
        guard audio.count <= 10 * 1024 * 1024 else {
            throw AppError.message("Recording is too large. Try a shorter dictation.")
        }
        guard vocabulary.utf16.count <= 1000 else {
            throw AppError.message("Vocabulary is too long. Shorten it in Settings.")
        }
        var request = URLRequest(url: base.appendingPathComponent("v1/transcribe"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(TranscriptionPayload(
            audio: audio.base64EncodedString(), language: language.isEmpty ? nil : language,
            vocabulary: vocabulary.isEmpty ? nil : vocabulary, requestId: id.uuidString))
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AppError.message("No response from the transcription service.") }
        guard http.statusCode == 200 else {
            let remote = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw TranscriptionServiceError(status: http.statusCode, code: remote?.error.code ?? "UNKNOWN",
                                            message: remote?.error.message ?? "Transcription failed (HTTP \(http.statusCode)).")
        }
        let reply = try JSONDecoder().decode(TranscriptionReply.self, from: data)
        guard reply.requestId.lowercased() == id.uuidString.lowercased() else {
            throw AppError.message("The service returned a different recording ID. Nothing was inserted.")
        }
        return reply
    }
    static func transcribe(file: URL, id: UUID, endpoint: String, token: String,
                           language: String, vocabulary: String, session: URLSession = session,
                           progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> TranscriptionReply {
        let chunks = try WAVChunks(url: file)
        var text: [String] = []
        var duration = 0.0
        var model = ""
        for index in 0..<chunks.count {
            try Task.checkCancellation()
            await progress(index + 1, chunks.count)
            try Task.checkCancellation()
            do {
                let reply = try await transcribe(audio: chunks.chunk(at: index), id: UUID(), endpoint: endpoint,
                                                token: token, language: language, vocabulary: vocabulary, session: session)
                text.append(reply.text.trimmingCharacters(in: .whitespacesAndNewlines))
                duration += reply.durationMs; model = reply.model
            } catch let error as TranscriptionServiceError where error.status == 422 && error.code == "NO_SPEECH" {
                // A silent segment must not discard speech in the rest of a long recording.
                continue
            }
        }
        try Task.checkCancellation()
        let combined = text.filter { !$0.isEmpty }.joined(separator: " ")
        guard !combined.isEmpty else { throw AppError.message("No speech was detected. Try again closer to the microphone.") }
        return TranscriptionReply(text: combined, requestId: id.uuidString, model: model, durationMs: duration)
    }
    static func health(endpoint: String) async throws -> String {
        guard let base = Endpoint.validated(endpoint) else { throw AppError.message("Enter HTTPS, or HTTP on localhost.") }
        let (_, response) = try await session.data(from: base.appendingPathComponent("health"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.message("The service did not answer its health check.") }
        return "Service is reachable"
    }
}
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectDelegate()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
