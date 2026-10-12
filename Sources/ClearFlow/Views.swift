import SwiftUI
import ClearFlowCore

private enum FlowTheme {
    static let shell = Color(red: 0.965, green: 0.960, blue: 0.945)
    static let selected = Color(red: 0.934, green: 0.918, blue: 0.880)
    static let ink = Color(red: 0.15, green: 0.145, blue: 0.16)
    static let muted = Color(red: 0.47, green: 0.46, blue: 0.44)
    static let line = Color(red: 0.90, green: 0.885, blue: 0.86)
    static let orange = Color(red: 1, green: 0.67, blue: 0.28)
}
private struct FlowButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 17).padding(.vertical, 11)
            .foregroundStyle(FlowTheme.ink)
            .background(prominent ? FlowTheme.orange : FlowTheme.selected,
                        in: RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
struct MainView: View {
    var renderForDocumentation = false
    @ObservedObject var model: DictationModel
    @State private var page = "Dictation"
    @State private var showSettings = false
    @State private var query = ""
    @State private var searching = false
    private var words: Int { model.history.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count } }
    private var filtered: [Transcript] {
        model.history.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sidebar.left").font(.system(size: 16)).foregroundStyle(FlowTheme.muted)
                Spacer()
                Text("ClearFlow").font(.system(size: 12, weight: .medium)).foregroundStyle(FlowTheme.muted)
            }.padding(.horizontal, 24).frame(height: 42)
            HStack(spacing: 0) {
                sidebar
                VStack(alignment: .leading, spacing: 0) {
                    if page == "Dictation" { dictation } else { dictionary }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(FlowTheme.line, lineWidth: 1))
                .padding(.trailing, 12).padding(.bottom, 12)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(FlowTheme.shell)
        .foregroundStyle(FlowTheme.ink).tint(FlowTheme.ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSettings) { FlowSettings(model: model) }
        .onAppear { model.refreshPermissions() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 24, weight: .semibold))
                Text("ClearFlow").font(.system(size: 23, weight: .semibold))
            }.padding(.horizontal, 14).padding(.top, 23).padding(.bottom, 27)
            nav("Dictation", icon: "mic")
            nav("Dictionary", icon: "book.closed")
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("Make yourself heard").font(.system(size: 12, weight: .semibold))
                Text("Press \(model.shortcut.display)\nto start and finish.")
                    .font(.system(size: 12)).foregroundStyle(FlowTheme.muted).lineSpacing(4)
                HStack(spacing: 3) { ForEach(model.shortcut.keycaps, id: \.self) { keycap($0) } }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(FlowTheme.line))
                .padding(.horizontal, 8).padding(.bottom, 16)
            Rectangle().fill(FlowTheme.line).frame(height: 1).padding(.horizontal, 10)
            Button { model.refreshPermissions(); showSettings = true } label: {
                Label("Settings", systemImage: "gearshape").font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(13)
            }.buttonStyle(.plain).padding(.top, 6)
            HStack(spacing: 6) {
                Circle().fill(model.hasToken ? Color(red: 0.13, green: 0.43, blue: 0.37) : .orange).frame(width: 5, height: 5)
                Text("Your transcription service").font(.system(size: 10))
            }.foregroundStyle(FlowTheme.muted).opacity(model.hasToken ? 1 : 0)
                .padding(.horizontal, 14).padding(.bottom, 16)
        }.padding(.horizontal, 10).frame(width: 196)
    }
    private func nav(_ name: String, icon: String) -> some View {
        Button { page = name } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 21)
                Text(name).font(.system(size: 15))
                Spacer()
            }.padding(.horizontal, 14).frame(height: 43)
                .background(page == name ? FlowTheme.selected : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 5)
            .background(FlowTheme.shell, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(FlowTheme.line))
    }
    private var dictation: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Welcome back").font(.system(size: 28, weight: .medium))
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 24) {
                    banner
                    if !model.hasAccessibility {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "hand.raised")
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Automatic insertion needs Accessibility access.").font(.system(size: 12, weight: .medium))
                                Button("Open insertion settings") { model.refreshPermissions(); showSettings = true }
                                    .buttonStyle(.plain).font(.system(size: 12)).underline()
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(FlowTheme.selected, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if model.mode == .error || model.mode == .ready {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: model.mode == .error ? "exclamationmark.circle" : model.status.hasPrefix("Inserted") ? "checkmark.circle" : "doc.on.clipboard")
                            VStack(alignment: .leading, spacing: 8) {
                                Text(model.status).font(.system(size: 12)).textSelection(.enabled)
                                if !model.transcript.isEmpty { Button("Copy transcript") { model.copy() }.buttonStyle(.plain).underline() }
                                if model.canRetry { Button("Retry transcription") { model.retry() }.buttonStyle(FlowButton()) }
                            }
                            Spacer(minLength: 0)
                        }.padding(14).background(FlowTheme.shell, in: RoundedRectangle(cornerRadius: 10))
                    }
                    history
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                stats.frame(width: 174)
            }
        }.padding(32)
    }
    private var banner: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.15, green: 0.17, blue: 0.15))
            // Original decorative artwork; no packaged Wispr assets.
            HStack(alignment: .center, spacing: 7) {
                ForEach(0..<11, id: \.self) { i in
                    Capsule().fill(Color(red: 0.76, green: 0.73, blue: 0.59).opacity(0.20))
                        .frame(width: 10, height: CGFloat(35 + (i * 29) % 95))
                }
            }.rotationEffect(.degrees(-14)).padding(.trailing, 12).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 13) {
                Text(model.mode == .recording ? "Go on. We’re listening." : model.mode == .transcribing ? "Finding your words." : "Less typing.\nMore you.")
                    .font(.system(size: 29, weight: .regular, design: .serif))
                    .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.91)).lineSpacing(0)
                Text(model.mode == .recording ? "Press \(model.shortcut.display) when you’re done." : model.mode == .transcribing ? "Your transcript will be ready in a moment." : "Speak naturally, wherever you write.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.80))
                HStack(spacing: 9) {
                    Button { model.toggle() } label: {
                        Text(model.mode == .recording ? "Finish dictation" : model.busy ? "Cancel" : "Start dictation")
                    }.buttonStyle(FlowButton())
                    if model.mode == .recording {
                        Button("Cancel") { model.cancel() }.buttonStyle(.plain).foregroundStyle(.white)
                        Text(String(format: "%d:%02d", Int(model.seconds)/60, Int(model.seconds)%60))
                            .monospacedDigit().foregroundStyle(.white).font(.caption)
                    }
                }.padding(.top, 5)
            }.padding(25).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 220)
    }
    private var stats: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                stat("\(words)", "words")
                stat("\(model.history.count)", "dictations")
            }.padding(22)
            Rectangle().fill(FlowTheme.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("Your words,\nyour way.").font(.system(size: 16, weight: .medium))
                Text("Add names and terms you use often for a more personal vocabulary.")
                    .font(.system(size: 12)).foregroundStyle(FlowTheme.muted).lineSpacing(3)
                Button("Open dictionary") { page = "Dictionary" }.buttonStyle(FlowButton(prominent: true))
            }.padding(18)
            Text("Based on recent history").font(.system(size: 10)).foregroundStyle(FlowTheme.muted)
                .padding(.horizontal, 18).padding(.bottom, 16)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(FlowTheme.shell, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(FlowTheme.line))
    }
    private func stat(_ number: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(number).font(.system(size: 30, design: .serif))
            Text(label).font(.system(size: 12))
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("RECENT DICTATIONS").font(.system(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(FlowTheme.muted)
                Spacer()
                Button { searching.toggle(); if !searching { query = "" } } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 15))
                }.buttonStyle(.plain).foregroundStyle(FlowTheme.muted).help("Search transcripts")
            }
            if searching {
                TextField("Search your dictations", text: $query).textFieldStyle(.roundedBorder)
            }
            HistoryContainer(renderForDocumentation: renderForDocumentation) {
                if filtered.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: query.isEmpty ? "text.bubble" : "magnifyingglass").font(.system(size: 25)).foregroundStyle(FlowTheme.muted)
                        Text(query.isEmpty ? "Your next thought starts here" : "No matching dictations")
                            .font(.system(size: 16, weight: .medium))
                        Text(query.isEmpty ? "Press \(model.shortcut.display), say what’s on your mind,\nthen press it again. Your words will appear here." : "Try another word or phrase.")
                            .font(.system(size: 12)).foregroundStyle(FlowTheme.muted).multilineTextAlignment(.center).lineSpacing(4)
                    }.frame(maxWidth: .infinity).padding(.vertical, 38)
                } else {
                    VStack(spacing: 0) {
                        ForEach(filtered) { item in
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.date, style: .time)
                                    if !Calendar.current.isDateInToday(item.date) { Text(item.date, format: .dateTime.month(.abbreviated).day()) }
                                }.font(.system(size: 11)).foregroundStyle(FlowTheme.muted).frame(width: 62, alignment: .leading)
                                Text(item.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button { model.copy(item.text) } label: { Image(systemName: "square.on.square") }
                                    .buttonStyle(.plain).foregroundStyle(FlowTheme.muted).help("Copy transcript")
                            }.padding(18)
                            if item.id != filtered.last?.id { Rectangle().fill(FlowTheme.line).frame(height: 1) }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(FlowTheme.line))
            Text(model.saveHistory ? "Saved on this Mac" : "This session only · History saving is off")
                .font(.system(size: 10)).foregroundStyle(FlowTheme.muted)
        }.frame(maxHeight: .infinity)
    }
    private var dictionary: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Dictionary").font(.system(size: 30, design: .serif))
            Text("A little context goes a long way.").font(.system(size: 18, weight: .medium))
            Text("Add names, places, and specialist terms you use. ClearFlow sends these as vocabulary hints when it transcribes your voice.")
                .font(.system(size: 14)).foregroundStyle(FlowTheme.muted).lineSpacing(5).frame(maxWidth: 550, alignment: .leading)
            VStack(alignment: .leading, spacing: 14) {
                Text("Your vocabulary").font(.system(size: 14, weight: .medium))
                TextEditor(text: $model.vocabulary).font(.system(size: 15))
                    .scrollContentBackground(.hidden).padding(12).frame(height: 180)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(FlowTheme.line))
                HStack {
                    Text("Separate words with commas. Up to 1,000 characters.")
                        .font(.system(size: 11)).foregroundStyle(FlowTheme.muted)
                    Spacer()
                    Button("Save dictionary") { model.saveSettings() }.buttonStyle(FlowButton(prominent: true))
                }
            }.padding(24).background(FlowTheme.shell, in: RoundedRectangle(cornerRadius: 16))
            Text(model.settingsMessage).font(.system(size: 12)).foregroundStyle(FlowTheme.muted)
            Spacer()
        }.padding(36)
    }
}
private struct FlowSettings: View {
    @ObservedObject var model: DictationModel
    @Environment(\.dismiss) private var dismiss
    @State private var section = "General"
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SETTINGS").font(.system(size: 11, weight: .medium)).tracking(1).foregroundStyle(FlowTheme.muted)
                    .padding(.horizontal, 12).padding(.top, 25).padding(.bottom, 14)
                sectionButton("General", "slider.horizontal.3")
                sectionButton("Transcription", "waveform")
                sectionButton("Data & privacy", "hand.raised")
                Spacer()
                Text("ClearFlow " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")).font(.system(size: 11)).foregroundStyle(FlowTheme.muted).padding(14)
            }.padding(10).frame(width: 174).background(FlowTheme.shell)
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(section).font(.system(size: 30, design: .serif))
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(FlowTheme.muted) }
                        .buttonStyle(.plain).help("Close settings")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if section == "General" { general }
                        else if section == "Transcription" { service }
                        else { privacy }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(FlowTheme.shell, in: RoundedRectangle(cornerRadius: 14))
                }
                HStack(alignment: .center, spacing: 15) {
                    Text(model.settingsMessage).font(.system(size: 11)).foregroundStyle(FlowTheme.muted).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("Save changes") { model.saveSettings() }.buttonStyle(FlowButton(prominent: true))
                }
            }.padding(32).frame(maxWidth: .infinity).background(.white)
        }.frame(width: 790, height: 550).foregroundStyle(FlowTheme.ink).tint(FlowTheme.ink).preferredColorScheme(.light)
    }
    private func sectionButton(_ name: String, _ icon: String) -> some View {
        Button { section = name } label: {
            Label(name, systemImage: icon).font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(section == name ? FlowTheme.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
    private func rule() -> some View { Rectangle().fill(FlowTheme.line).frame(height: 1).padding(.vertical, 21) }
    private func row(_ title: String, _ detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(FlowTheme.muted)
            }
            Spacer()
            if granted { Label("Enabled", systemImage: "checkmark").font(.system(size: 12)) }
            else { Button("Enable", action: action).buttonStyle(FlowButton()) }
        }
    }
    private var general: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shortcut").font(.system(size: 14, weight: .medium))
                    Text("Press once to speak. Press again to finish.").font(.system(size: 12)).foregroundStyle(FlowTheme.muted)
                }
                Spacer()
                ShortcutRecorder(model: model).frame(width: 165, height: 34)
            }
            Text(model.shortcutMessage.isEmpty ? "Click the shortcut, then press the new key combination." : model.shortcutMessage)
                .font(.caption).foregroundStyle(FlowTheme.muted).padding(.top, 8)
            if model.shortcut.isFn {
                Text("Tap Fn to start or finish. In macOS Keyboard settings, set ‘Press 🌐 key to’ to ‘Do Nothing’. Disable Fn in other dictation apps to avoid conflicts.")
                    .font(.caption).foregroundStyle(FlowTheme.muted).padding(.top, 8)
            }
            if !model.shortcutAvailable { Text(model.shortcut.isFn && !model.hasAccessibility
                ? "Fn is saved. Enable Accessibility below, then refresh permission status to activate it."
                : "This shortcut is unavailable. Choose another combination above, or use Start dictation.")
                .font(.caption).foregroundStyle(.orange).padding(.top, 8) }
            rule()
            row("Microphone", "Use your Mac’s default input.", granted: model.microphoneGranted) { model.requestMicrophone() }
            rule()
            row("Automatic insertion", "Allow Accessibility to type into other apps.", granted: model.hasAccessibility) { model.grantAccessibility() }
            Button("Refresh permission status") { model.refreshPermissions() }
                .buttonStyle(.plain).font(.system(size: 11)).underline().padding(.top, 14)
            Button("Test automatic insertion") { model.testInsertion() }
                .buttonStyle(FlowButton()).disabled(model.busy).padding(.top, 14)
            Text("Select a disposable text field in another app, return here, then test. Inserts: ClearFlow insertion test.")
                .font(.system(size: 11)).foregroundStyle(FlowTheme.muted).padding(.top, 8)
            rule()
            Text("Dictation language").font(.system(size: 14, weight: .medium))
            TextField("Auto-detect, or en / es / fr", text: $model.language)
                .textFieldStyle(.roundedBorder).padding(.top, 10)
        }
    }
    private var service: some View {
        Group {
            Text("Your transcription service").font(.system(size: 16, weight: .medium))
            Text("Local Whisper or your own hosted backend").font(.system(size: 12)).foregroundStyle(FlowTheme.muted).padding(.top, 7)
            rule()
            Text("Service address").font(.system(size: 13, weight: .medium))
            TextField("http://127.0.0.1:8768", text: $model.endpoint).textFieldStyle(.roundedBorder).padding(.top, 10)
            Text("Access token").font(.system(size: 13, weight: .medium)).padding(.top, 20)
            SecureField(model.hasToken ? "Saved in Keychain — leave blank to keep" : "Private service token", text: $model.token)
                .textFieldStyle(.roundedBorder).padding(.top, 10)
            Button("Check connection") { model.testConnection() }.buttonStyle(FlowButton()).padding(.top, 20)
            Text("Transcription begins when you finish speaking. Up to 4 minutes 55 seconds per recording.")
                .font(.system(size: 12)).foregroundStyle(FlowTheme.muted).lineSpacing(3).padding(.top, 20)
        }
    }
    private var privacy: some View {
        Group {
            Toggle("Save recent transcripts on this Mac", isOn: $model.saveHistory).font(.system(size: 13, weight: .medium))
            Text("When off, recent dictations stay in memory. Turning this off and saving removes the saved history file.")
                .font(.system(size: 12)).foregroundStyle(FlowTheme.muted).lineSpacing(4).padding(.top, 10)
            rule()
            Text("Your audio").font(.system(size: 14, weight: .medium))
            Text("Audio is sent only to the service address you configure when you finish. Local Whisper runs on your own hardware; a cloud endpoint sends audio to that provider. There is no automatic cloud fallback. Temporary recordings are deleted on normal finish or cancel. Failed requests can keep audio in memory so you can retry.")
                .font(.system(size: 12)).foregroundStyle(FlowTheme.muted).lineSpacing(4).padding(.top, 9)
            Text("No screen content is uploaded.").font(.system(size: 12)).padding(.top, 12)
            rule()
            Button("Clear recent history") { model.clearHistory() }.buttonStyle(FlowButton())
        }
    }
}
private struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: DictationModel
    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(frame: .zero)
        button.onBegin = { model.beginShortcutRecording() }
        button.onEnd = { model.endShortcutRecording() }
        button.onCapture = { model.changeShortcut($0) }
        button.onMessage = { model.shortcutMessage = $0 }
        return button
    }
    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.savedTitle = model.shortcut.display
        button.isEnabled = !model.busy
        if model.busy { button.cancelRecording() }
    }
    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) {
        button.cancelRecording()
    }
}
struct Waveform: View {
    let samples: [Double]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(samples.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white).frame(width: 2, height: max(1.5, 13 * samples[index]))
            }
        }.frame(width: 38, height: 14)
            .animation(.linear(duration: 0.05), value: samples)
            .accessibilityLabel("Microphone level")
    }
}
struct RecordingBar: View {
    let samples: [Double]
    let recording: Bool
    let processingLabel: String
    // Deterministic spinner for offscreen documentation only; normal UI uses ProgressView.
    var previewRotation: Double? = nil
    let onCancel: () -> Void
    let onFinish: () -> Void
    var body: some View {
        HStack(spacing: 5) {
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color(red: 0.31, green: 0.30, blue: 0.28), in: Circle())
                    .contentShape(Circle())
            }.buttonStyle(.plain).help("Cancel dictation").accessibilityLabel("Cancel dictation")
            if recording {
                Waveform(samples: samples)
            } else if let previewRotation {
                Circle().trim(from: 0.08, to: 0.80)
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 10, height: 10).rotationEffect(.degrees(previewRotation))
                    .frame(width: 38, height: 14).accessibilityLabel(processingLabel)
            } else {
                ProgressView().controlSize(.mini).colorScheme(.dark)
                    .frame(width: 38, height: 14)
                    .accessibilityLabel(processingLabel).help(processingLabel)
            }
            Button(action: onFinish) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(recording ? 1 : 0.4), in: Circle())
                    .contentShape(Circle())
            }.buttonStyle(.plain).disabled(!recording).help("Finish dictation").accessibilityLabel("Finish dictation")
        }.padding(.horizontal, 7).frame(width: 102, height: 30)
            .background(.black, in: Capsule())
            .overlay(Capsule().stroke(Color(red: 0.23, green: 0.23, blue: 0.21), lineWidth: 1))
    }
}
struct OverlayView: View {
    @ObservedObject var model: DictationModel
    var body: some View {
        RecordingBar(samples: model.meter.samples, recording: model.mode == .recording,
                     processingLabel: model.mode == .testingInsertion ? "Testing" : model.mode == .transcribing ? "Transcribing" : "Microphone",
                     onCancel: { model.cancel() }, onFinish: { model.stop() })
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2).padding(8)
    }
}

private struct HistoryContainer<Content: View>: View {
    let renderForDocumentation: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if renderForDocumentation { VStack { content(); Spacer(minLength: 0) } }
        else { ScrollView { content() } }
    }
}
