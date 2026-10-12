import Foundation
import AVFoundation

@MainActor final class AudioCapture: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var file: URL?
    var onAutomaticStop: (() -> Void)?
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
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.delegate = self; r.isMeteringEnabled = true
        guard r.prepareToRecord(), r.record(forDuration: 295) else {
            try? FileManager.default.removeItem(at: url)
            throw AppError.message("The microphone could not start. Check the selected input in System Settings.")
        }
        recorder = r; file = url
    }
    func stop() throws -> Data {
        guard let recorder, let file else { throw AppError.message("No recording is active.") }
        recorder.delegate = nil
        recorder.stop()
        self.recorder = nil; self.file = nil
        defer { try? FileManager.default.removeItem(at: file) }
        let data = try Data(contentsOf: file)
        guard data.count > 8044 else { throw AppError.message("That recording was too short. Speak for at least a moment.") }
        return data
    }
    func cancel() {
        recorder?.delegate = nil; recorder?.stop(); recorder = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onAutomaticStop?() }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in self?.onAutomaticStop?() }
    }
}
