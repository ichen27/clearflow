import AppKit
import SwiftUI

/// Reproducible documentation renders. No capture, network, paste or saved history.
@MainActor enum MediaPreview {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = DictationModel(demo: true)
        try save(MainView(renderForDocumentation: true, model: model).frame(width: 1120, height: 780),
                 to: directory.appendingPathComponent("screenshot.png"))
        let recovery = DictationModel(demo: true)
        recovery.mode = .ready
        recovery.recordingNotice = "Recording stopped unexpectedly. Your recovered transcript is saved in Recent Dictations."
        try save(OverlayView(model: recovery).frame(width: 360, height: 200),
                 to: directory.appendingPathComponent("recovery-warning.png"))
        for frame in 0..<48 {
            try save(Walkthrough(frame: frame).frame(width: 960, height: 560),
                     to: directory.appendingPathComponent(String(format: "frame-%03d.png", frame)))
        }
    }
    private static func save<V: View>(_ view: V, to url: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.locale, Locale(identifier: "en_US")).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
private struct Walkthrough: View {
    let frame: Int
    private var phase: Int { frame < 8 ? 0 : frame < 32 ? 1 : frame < 38 ? 2 : 3 }
    private let text = "Let’s make a little more room for ideas."
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("ClearFlow", systemImage: "waveform").font(.system(size: 24, weight: .semibold))
                Spacer()
                Text("LOCAL WHISPER").font(.system(size: 11, weight: .semibold)).tracking(2)
            }
            Text(["1  ·  Select a text field", "2  ·  Press ⌥ ⇧ Space and speak", "3  ·  Press again to transcribe", "4  ·  Your words appear in place"][phase])
                .font(.system(size: 20, weight: .medium))
            VStack(alignment: .leading, spacing: 22) {
                HStack { Circle().fill(Color.orange).frame(width: 8, height: 8); Text("Sample editor").font(.system(size: 12)); Spacer() }
                Text("A little more room for ideas").font(.system(size: 28, design: .serif))
                Text(phase == 3 ? text : "│").font(.system(size: 19)).frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                HStack {
                    Spacer()
                    if phase == 1 || phase == 2 {
                        RecordingBar(samples: (0..<10).map { i in abs(sin(Double(frame + i) * 0.79)) * 0.9 },
                                     recording: phase == 1, processingLabel: "Transcribing", onCancel: {}, onFinish: {})
                    } else { Color.clear.frame(width: 102, height: 30) }
                    Spacer()
                }
            }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
            Text("UI walkthrough · Synthetic text and waveform · Illustrates the flow; no live inference or paste")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(36).background(Color(red: 0.965, green: 0.960, blue: 0.945))
            .foregroundStyle(Color(red: 0.15, green: 0.145, blue: 0.16)).preferredColorScheme(.light)
    }
}
