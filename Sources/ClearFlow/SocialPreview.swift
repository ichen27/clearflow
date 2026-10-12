import AppKit
import SwiftUI

/// Synthetic, deterministic promotional media. Does not record, transcribe or paste.
@MainActor enum SocialPreview {
    static let fps = 24
    static let seconds = 23
    static func render(to directory: URL, portrait: Bool) throws {
        _ = NSApplication.shared
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = DictationModel(demo: true)
        let size = portrait ? CGSize(width: 720, height: 900) : CGSize(width: 1280, height: 720)
        for frame in 0..<(fps * seconds) {
            try autoreleasepool {
                let view = RevealFrame(time: Double(frame) / Double(fps), portrait: portrait, model: model)
                    .frame(width: size.width, height: size.height)
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                guard let cgImage = renderer.cgImage,
                      let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: directory.appendingPathComponent(String(format: "frame-%04d.png", frame)))
            }
        }
        print("Rendered \(fps * seconds) synthetic reveal frames.")
    }
}
private struct RevealFrame: View {
    let time: Double
    let portrait: Bool
    @ObservedObject var model: DictationModel
    private let ink = Color(red: 0.12, green: 0.14, blue: 0.13)
    private let paper = Color(red: 0.972, green: 0.962, blue: 0.938)
    private let amber = Color(red: 1, green: 0.68, blue: 0.30)
    private let sample = "Let’s make a little more room for ideas."
    private var phase: Int { time < 3 ? 0 : time < 6 ? 1 : time < 10 ? 2 : time < 12.5 ? 3 : time < 16 ? 4 : time < 19 ? 5 : 6 }
    private var start: Double { [0, 3, 6, 10, 12.5, 16, 19][phase] }
    private var entrance: Double { min(1, max(0, (time - start) / 0.38)) }
    private var rise: Double { pow(1 - entrance, 3) * 16 }
    private var samples: [Double] { (0..<10).map { i in
        let wave = abs(sin(time * 7.2 + Double(i) * 0.72))
        return 0.08 + wave * (0.42 + 0.45 * abs(sin(time * 2.7)))
    } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("ClearFlow", systemImage: "waveform").font(.system(size: portrait ? 28 : 27, weight: .semibold))
                Spacer()
                Text("SAMPLE UI DEMO").font(.system(size: portrait ? 11 : 12, weight: .medium)).tracking(2)
                    .foregroundStyle(ink.opacity(0.58))
            }.padding(.bottom, portrait ? 40 : 28)
            Group {
                if phase == 0 { intro }
                else if phase <= 4 { editor }
                else if phase == 5 { hub }
                else { outro }
            }.opacity(entrance).offset(y: rise).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text("OPEN SOURCE  /  LOCAL WHISPER").tracking(1.5)
                Spacer()
                Text("macOS · Apple Silicon")
            }.font(.system(size: portrait ? 11 : 12, weight: .medium)).foregroundStyle(ink.opacity(0.60))
                .padding(.top, 22)
            GeometryReader { geometry in
                Capsule().fill(ink.opacity(0.09)).overlay(alignment: .leading) {
                    Capsule().fill(amber).frame(width: geometry.size.width * min(1, time / 23))
                }
            }.frame(height: 3).padding(.top, 18)
        }.padding(portrait ? 38 : 44).background(paper).foregroundStyle(ink).preferredColorScheme(.light)
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: portrait ? 28 : 16) {
            Text("MEET CLEARFLOW").font(.system(size: 14, weight: .medium)).tracking(4).foregroundStyle(ink.opacity(0.6))
            Text("Your voice.\nYour Mac.").font(.system(size: portrait ? 80 : 86, weight: .regular, design: .serif)).lineSpacing(-8)
            Text("Dictation you can run yourself.").font(.system(size: portrait ? 25 : 27))
                .foregroundStyle(ink.opacity(0.65))
            HStack {
                Spacer()
                RecordingBar(samples: samples, recording: true, processingLabel: "", onCancel: {}, onFinish: {})
                    .scaleEffect(portrait ? 2.9 : 2.5).frame(width: 330, height: 100)
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 10)
                Spacer()
            }.padding(.top, portrait ? 35 : 6)
            Text("Local Whisper. No cloud account required.")
                .font(.system(size: portrait ? 20 : 22)).frame(maxWidth: .infinity).padding(.top, 10)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(["", "01 / Start where you write.", "02 / Speak naturally.", "03 / Transcribe locally.", "04 / Keep your flow."][phase])
                .font(.system(size: portrait ? 31 : 38, weight: .medium))
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 10) {
                    Circle().fill(amber).frame(width: 8, height: 8)
                    Text("SAMPLE EDITOR").font(.system(size: 11, weight: .medium)).tracking(2)
                    Spacer()
                    Text(phase == 3 ? "WHISPER" : "⌥ ⇧ SPACE").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9).background(paper, in: Capsule())
                }
                Text(portrait ? "A little more room\nfor ideas." : "A little more room for ideas.").font(.system(size: portrait ? 38 : 40, design: .serif)).fixedSize(horizontal: false, vertical: true).lineSpacing(1)
                Text(phase == 4 ? sample : "│").font(.system(size: portrait ? 25 : 26)).lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                HStack {
                    Spacer()
                    if phase == 2 || phase == 3 {
                        RecordingBar(samples: samples, recording: phase == 2, processingLabel: "Transcribing", previewRotation: time * 240, onCancel: {}, onFinish: {})
                            .scaleEffect(1.7).frame(width: 180, height: 52)
                    } else if phase == 4 {
                        Label("Back to your words", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14)).foregroundStyle(Color(red: 0.2, green: 0.42, blue: 0.32)).frame(height: 52)
                    } else { Color.clear.frame(height: 52) }
                    Spacer()
                }
            }.padding(portrait ? 28 : 32).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(ink.opacity(0.08)))
            VStack(alignment: .leading, spacing: 8) {
                Text(phase == 1 ? "Select a field. Press Option–Shift–Space." : phase == 2 ? "Say it: “Let’s make a little more room for ideas.”" : phase == 3 ? "Press again to finish. Whisper runs on your hardware." : "Guarded insertion, with clipboard fallback.")
                    .font(.system(size: portrait ? 18 : 19)).fixedSize(horizontal: false, vertical: true)
                Text("Illustrated sequence · Synthetic input · Overlay enlarged · Timing not measured")
                    .font(.system(size: portrait ? 10 : 11)).foregroundStyle(ink.opacity(0.5))
            }
        }
    }
    private var hub: some View {
        Group {
            if portrait {
                VStack(alignment: .leading, spacing: 24) {
                    Text("A home for your words.").font(.system(size: 36, weight: .medium))
                    hubScreenshot(scale: 0.56).frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text("Native macOS app. Optional history. Your own vocabulary.")
                        .font(.system(size: 19)).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 50) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("A home for\nyour words.").font(.system(size: 44, weight: .medium))
                        Text("Native macOS app.\nOptional history.\nYour own vocabulary.")
                            .font(.system(size: 23)).lineSpacing(10).foregroundStyle(ink.opacity(0.65))
                    }.frame(width: 350, alignment: .leading)
                    hubScreenshot(scale: 0.56)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    private func hubScreenshot(scale: CGFloat) -> some View {
        MainView(renderForDocumentation: true, model: model).frame(width: 1120, height: 780)
            .scaleEffect(scale).frame(width: 1120 * scale, height: 780 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 16)).compositingGroup()
            .shadow(color: .black.opacity(0.09), radius: 12, y: 5)
    }
    private var outro: some View {
        VStack(alignment: .leading, spacing: portrait ? 30 : 20) {
            Text("CLEARFLOW IS OPEN SOURCE").font(.system(size: 13, weight: .medium)).tracking(3)
                .foregroundStyle(ink.opacity(0.6))
            Text(portrait ? "Less typing.\nMore you." : "Less typing. More you.").font(.system(size: portrait ? 80 : 90, weight: .regular, design: .serif)).lineSpacing(-8)
            Text(portrait ? "Whisper large-v3-turbo\non your own hardware." : "Whisper large-v3-turbo on your own hardware.").font(.system(size: portrait ? 28 : 30)).lineSpacing(5)
            HStack {
                Text("Get the app + source").font(.system(size: 19, weight: .medium))
                Image(systemName: "arrow.up.right").font(.system(size: 18, weight: .medium))
            }.padding(.horizontal, 22).padding(.vertical, 17).background(amber, in: RoundedRectangle(cornerRadius: 12))
            Text("github.com/ichen27/clearflow").font(.system(size: portrait ? 21 : 23, weight: .medium))
            Text("Apple Silicon · macOS 14+ · Setup required")
                .font(.system(size: 13)).foregroundStyle(ink.opacity(0.6))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
