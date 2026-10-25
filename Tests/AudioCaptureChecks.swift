import Foundation
import AVFoundation

final class ClockRecorder: AudioRecording {
    var delegate: AVAudioRecorderDelegate?
    var isMeteringEnabled = false
    var currentTime: TimeInterval = 0
    var deadline = Double.infinity
    var active = false
    func prepareToRecord() -> Bool { true }
    func record() -> Bool { currentTime = 0; active = true; return true }
    func record(forDuration duration: TimeInterval) -> Bool { deadline = duration; return record() }
    func updateMeters() {}
    func averagePower(forChannel channel: Int) -> Float { -30 }
    func advance(to time: Double) { currentTime = min(time, deadline); if time >= deadline { active = false } }
    func stop() { active = false }
}
@main enum AudioCaptureChecks {
    @MainActor static func main() throws {
        let recorder = ClockRecorder()
        var file: URL?
        let capture = AudioCapture { url, _ in
            file = url
            try Data(repeating: 0, count: 32044).write(to: url)
            return recorder
        }
        try capture.start()
        recorder.advance(to: 3600)
        guard recorder.active, capture.seconds == 3600 else {
            fputs("FAIL: capture stopped before the user stopped it (simulated 60-minute clock).\n", stderr)
            exit(1)
        }
        capture.cancel()
        guard !recorder.active else { fatalError("Cancel must stop the recorder") }
        guard !FileManager.default.fileExists(atPath: file!.path) else { fatalError("Cancel must delete audio") }
        try capture.start()
        var audio: RecordedAudio? = try capture.stop()
        guard !recorder.active, FileManager.default.fileExists(atPath: audio!.url.path) else { fatalError("Explicit stop must retain audio for transcription") }
        let saved = audio!.url
        audio = nil
        guard !FileManager.default.fileExists(atPath: saved.path) else { fatalError("Releasing a completed/cancelled request must delete temporary audio") }
        print("PASS: capture remains active at 60 minutes (simulated clock); explicit stop/cancel and temporary file lifetime")
    }
}
