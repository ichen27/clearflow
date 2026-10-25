import Foundation
import AVFoundation

protocol AudioRecording: AnyObject {
    var delegate: AVAudioRecorderDelegate? { get set }
    var isMeteringEnabled: Bool { get set }
    var currentTime: TimeInterval { get }
    func updateMeters()
    func averagePower(forChannel channel: Int) -> Float
    func prepareToRecord() -> Bool
    func record() -> Bool
    func record(forDuration duration: TimeInterval) -> Bool
    func stop()
}
extension AVAudioRecorder: AudioRecording {}

@MainActor final class AudioCapture: NSObject, AVAudioRecorderDelegate {
    private var recorder: AudioRecording?
    private let directory: URL
    private let makeRecorder: (URL, [String: Any]) throws -> AudioRecording
    init(directory: URL = RecordingStore.directory, makeRecorder: @escaping (URL, [String: Any]) throws -> AudioRecording = { try AVAudioRecorder(url: $0, settings: $1) }) {
        self.directory = directory
        self.makeRecorder = makeRecorder
        super.init()
    }
    private var file: URL?
    var onUnexpectedStop: ((String) -> Void)?
    var seconds: Double { recorder?.currentTime ?? 0 }
    var level: Double {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        return max(0, min(1, (Double(recorder.averagePower(forChannel: 0)) + 55) / 55))
    }
    func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav").standardizedFileURL
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: false
        ]
        let r = try makeRecorder(url, settings)
        r.delegate = self; r.isMeteringEnabled = true
        guard r.prepareToRecord() else {
            try? FileManager.default.removeItem(at: url)
            throw AppError.message("The microphone could not prepare. Check your input device.")
        }
        do { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
        guard r.record() else {
            try? FileManager.default.removeItem(at: url)
            throw AppError.message("The microphone could not start. Check the selected input in System Settings.")
        }
        recorder = r; file = url
    }
    func stop() throws -> RecordedAudio {
        guard let recorder, let file else { throw AppError.message("No recording is active.") }
        recorder.delegate = nil
        recorder.stop()
        self.recorder = nil; self.file = nil
        let recording = RecordedAudio(url: file)
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard (size?.intValue ?? 0) > 8044 else { throw AppError.message("That recording was too short. Speak for at least a moment.") }
        return recording
    }
    func cancel() {
        recorder?.delegate = nil; recorder?.stop(); recorder = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.onUnexpectedStop?("The microphone stopped unexpectedly. Check your input device and available disk space.")
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.onUnexpectedStop?("The microphone stopped unexpectedly. Check your input device and available disk space.")
        }
    }
}

/// Durable until explicitly discarded or a transcript has been saved successfully.
final class RecordedAudio {
    let url: URL
    init(url: URL) { self.url = url.standardizedFileURL }
    func discard() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

enum RecordingStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClearFlow/Recordings", isDirectory: true)
    }
    static func recordings(in directory: URL = directory) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey])
            .filter { $0.pathExtension == "wav" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.standardizedFileURL }
            .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
    }
}
