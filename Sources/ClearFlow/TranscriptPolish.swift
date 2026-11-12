import Foundation
import ClearFlowCore

/// Sends a cleaned transcript to Claude for a light copy edit. Opt-in; on any error,
/// timeout or implausible reply the caller keeps the cleaned text.
enum TranscriptPolish {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let timeout: TimeInterval = 8
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.urlCache = nil
        return URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
    }()
    static func polish(_ text: String, apiKey: String, model: String, vocabulary: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Polish.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(Polish.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONEncoder().encode(Polish.request(for: text, vocabulary: vocabulary, model: model))
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Polish.Failure.invalidResponse }
        guard status == 200 else {
            throw AppError.message(status == 401 ? "Claude rejected the API key." : "Claude returned HTTP \(status).")
        }
        guard let edited = Polish.accept(try Polish.text(from: data), original: text) else { throw Polish.Failure.rejected }
        return edited
    }
}
