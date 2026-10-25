import Foundation
import AVFoundation

final class RecoveryRecorder: AudioRecording {
    var delegate: AVAudioRecorderDelegate?
    var isMeteringEnabled = false
    var currentTime: TimeInterval = 30
    func prepareToRecord() -> Bool { true }
    func record() -> Bool { true }
    func record(forDuration duration: TimeInterval) -> Bool { true }
    func updateMeters() {}
    func averagePower(forChannel channel: Int) -> Float { -30 }
    func stop() {}
}

@main enum RecoveryChecks {
    @MainActor static func settle(_ model: DictationModel) async {
        for _ in 0..<200 {
            if !model.busy { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        fatalError("Model did not settle")
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let recordings = directory.appendingPathComponent("Recordings")
        var file: URL?
        let capture = AudioCapture(directory: recordings) { url, _ in
            file = url
            try Data(repeating: 0, count: 32044).write(to: url)
            return RecoveryRecorder()
        }
        try capture.start()
        var audio: RecordedAudio? = try capture.stop()
        guard audio != nil else { fatalError("Recording missing") }
        audio = nil
        guard FileManager.default.fileExists(atPath: file!.path) else {
            fatalError("Unfinished recording was deleted on owner release")
        }
        guard try RecordingStore.recordings(in: recordings).map({ $0.standardizedFileURL.path }) == [file!.standardizedFileURL.path] else { fatalError("Restart discovery lost recording") }
        try RecordedAudio(url: file!).discard()

        let model = DictationModel(demo: true, capture: capture, recoveryDirectory: recordings)
        model.history = []; model.saveHistory = true
        model.persistHistory = { try HistoryStore.save($0, to: historyURL) }
        model.transcribeRecording = { _, id in
            TranscriptionReply(text: "Synthetic recovered words.", requestId: id.uuidString, model: "test", durationMs: 30)
        }
        var inserted = 0
        model.insertTranscript = { text in
            guard HistoryStore.load(from: historyURL, enabled: true).first?.text == text else {
                fatalError("Insertion happened before durable transcript save")
            }
            inserted += 1
            return "Inserted"
        }
        model.beginCapture()
        model.stop()
        await settle(model)
        guard model.mode == .ready, inserted == 1,
              !FileManager.default.fileExists(atPath: file!.path) else { fatalError("Normal completion lifecycle") }
        // Re-read from disk to simulate a fresh process, not the in-memory history.
        guard HistoryStore.load(from: historyURL, enabled: true).count == 1 else { fatalError("Transcript lost on restart") }

        model.beginCapture()
        capture.onUnexpectedStop?("Synthetic device interruption.")
        guard !model.recordingNotice.isEmpty else { fatalError("Unexpected stop was silent") }
        await settle(model)
        guard model.mode == .ready, inserted == 1,
              HistoryStore.load(from: historyURL, enabled: true).count == 2,
              model.recordingNotice.contains("saved") else { fatalError("Interruption must save, warn and never paste") }

        model.persistHistory = { _ in throw AppError.message("Synthetic full disk") }
        model.beginCapture(); model.stop()
        await settle(model)
        guard model.mode == .error, model.canRetry, inserted == 1,
              FileManager.default.fileExists(atPath: file!.path) else { fatalError("Save failure must retain audio and block insertion") }
        let failedFile = file!
        // Starting a new recording must not delete a previously failed recording.
        model.beginCapture()
        let quittingFile = file!
        model.prepareForQuit()
        guard try RecordingStore.recordings(in: recordings).contains(failedFile),
              FileManager.default.fileExists(atPath: quittingFile.path) else { fatalError("Quit/start lost unfinished audio") }
        model.mode = .idle
        model.persistHistory = { try HistoryStore.save($0, to: historyURL) }
        model.refreshRecoveries()
        model.recover(quittingFile)
        await settle(model)
        guard model.mode == .ready, inserted == 1,
              !FileManager.default.fileExists(atPath: quittingFile.path) else { fatalError("Recovery must save without paste") }

        model.transcribeRecording = { _, _ in throw AppError.message("Synthetic network failure") }
        model.beginCapture(); model.stop()
        await settle(model)
        guard model.mode == .error, model.canRetry, !model.recordingNotice.isEmpty,
              FileManager.default.fileExists(atPath: file!.path) else { fatalError("Network failure lost audio") }
        // Explicit history-off must not silently persist text, but interrupted audio stays recoverable.
        model.saveHistory = false
        model.persistHistory = { _ in fatalError("History-off must not persist text") }
        model.transcribeRecording = { _, id in
            TranscriptionReply(text: "Private session.", requestId: id.uuidString, model: "test", durationMs: 1)
        }
        model.beginCapture()
        capture.onUnexpectedStop?("Synthetic interruption with history off")
        await settle(model)
        guard model.mode == .ready, FileManager.default.fileExists(atPath: file!.path) else { fatalError("History-off interruption lost audio") }
        model.saveHistory = true
        model.persistHistory = { try HistoryStore.save($0, to: historyURL) }
        model.transcribeRecording = { _, id in
            try await Task.sleep(nanoseconds: 500_000_000)
            return TranscriptionReply(text: "Do not deliver.", requestId: id.uuidString, model: "test", durationMs: 1)
        }
        model.beginCapture(); model.stop(); model.cancel()
        let cancelled = file!
        guard model.canRetry, FileManager.default.fileExists(atPath: cancelled.path) else { fatalError("Cancelled transcription must be recoverable") }
        let before = model.history.count
        try await Task.sleep(nanoseconds: 550_000_000)
        guard model.history.count == before else { fatalError("Cancelled result was delivered") }
        model.refreshRecoveries(); model.discardRecovery(cancelled)
        guard !FileManager.default.fileExists(atPath: cancelled.path) else { fatalError("Explicit discard failed") }

        model.beginCapture()
        let discarded = file!
        model.cancel()
        guard !FileManager.default.fileExists(atPath: discarded.path) else { fatalError("Explicit recording cancel must discard") }
        print("PASS: durable audio discovery; transcript saved before paste; interrupted auto-save and warning; disk/network failure; quit/new recording preservation; recovery; cancellation and explicit discard")
    }
}
