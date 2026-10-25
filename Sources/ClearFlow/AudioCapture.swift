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
    private let makeRecorder: (URL, [String: Any]) throws -> AudioRecording
    init(makeRecorder: @escaping (URL, [String: Any]) throws -> AudioRecording = { try AVAudioRecorder(url: $0, settings: $1) }) {
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClearFlow", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: false
        ]
        let r = try makeRecorder(url, settings)
        r.delegate = self; r.isMeteringEnabled = true
        guard r.prepareToRecord(), r.record() else {
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

/// Owns the temporary recording through transcription and retry; removes it on release.
final class RecordedAudio {
    let url: URL
    init(url: URL) { self.url = url }
    deinit { try? FileManager.default.removeItem(at: url) }
}
