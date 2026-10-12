import AppKit
import AVFoundation
import Combine
import ClearFlowCore

@MainActor final class DictationModel: ObservableObject {
    enum Mode { case idle, requestingPermission, recording, transcribing, testingInsertion, ready, error }
    @Published var mode: Mode = .idle
    @Published var status = "Your voice, wherever you type."
    @Published var seconds = 0.0
    @Published var level = 0.0
    @Published var meter = MeterHistory()
    @Published var transcript = ""
    @Published var history: [Transcript] = []
    @Published var endpoint = AppSettings.endpoint
    @Published var token = ""
    @Published var hasToken = false
    @Published var language = AppSettings.language
    @Published var vocabulary = AppSettings.vocabulary
    @Published var saveHistory = AppSettings.saveHistory
    @Published var settingsMessage = ""
    @Published var hasAccessibility = AXIsProcessTrusted()
    @Published var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var shortcutAvailable = true
    var showWindow: (() -> Void)?
    var lastExternalApp: NSRunningApplication?
    private var demoMode = false
    private let capture = AudioCapture()
    private var gate = SessionGate()
    private var currentID: UUID?
    private var target: InsertionTarget?
    private var captureIssue: String?
    private var pendingAudio: Data?
    private var ticker: Timer?
    private var requestTask: Task<Void, Never>?
    private var workspaceObserver: NSObjectProtocol?
    var busy: Bool { mode == .recording || mode == .transcribing || mode == .requestingPermission || mode == .testingInsertion }
    var canRetry: Bool { pendingAudio != nil && !busy }
    init(demo: Bool = false) {
        if demo {
            demoMode = true
            endpoint = "http://127.0.0.1:8768"; vocabulary = ""; token = ""
            saveHistory = false; hasAccessibility = true; microphoneGranted = true
            history = [Transcript(id: UUID(), date: Date(timeIntervalSince1970: 1780322400),
                text: "Let’s make a little more room for ideas. Speak naturally, then get back to what matters.", target: "Sample editor")]
            return
        }
        history = HistoryStore.load()
        hasToken = !TokenStore.read().isEmpty
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                Task { @MainActor [weak self] in self?.lastExternalApp = app }
            }
        capture.onAutomaticStop = { [weak self] in self?.stop() }
    }
    func refreshPermissions() {
        guard !demoMode else { return }
        hasAccessibility = AXIsProcessTrusted()
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    func grantAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
    }
    func requestMicrophone() {
        Task {
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
            if !microphoneGranted { settingsMessage = "Enable ClearFlow under System Settings → Privacy & Security → Microphone." }
        }
    }
    func toggle() {
        switch mode {
        case .recording: stop()
        case .transcribing, .requestingPermission, .testingInsertion: cancel()
        default: start()
        }
    }
    func start() {
        guard !busy else { return }
        guard Endpoint.validated(AppSettings.endpoint) != nil, !TokenStore.read().isEmpty else {
            status = "Connect your transcription service in Settings."; mode = .error; showWindow?(); return
        }
        let id = UUID()
        guard gate.begin(id) else { return }
        currentID = id
        refreshPermissions()
        let destination = TextInsertion.capture(previousApp: lastExternalApp)
        target = destination.target; captureIssue = destination.issue
        pendingAudio = nil
        mode = .requestingPermission; status = "Waiting for microphone access…"
        Task {
            let granted: Bool
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { granted = true }
            else { granted = await AVCaptureDevice.requestAccess(for: .audio) }
            guard currentID == id, mode == .requestingPermission else { return }
            microphoneGranted = granted
            guard granted else {
                gate.cancel(); mode = .error; status = "Microphone access is needed. Enable it in System Settings."; return
            }
            do {
                try capture.start()
                seconds = 0; level = 0; meter.reset(); transcript = ""
                mode = .recording; status = "Listening"
                ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.mode == .recording else { return }
                        self.seconds = self.capture.seconds; self.level = self.capture.level
                        self.meter.append(self.level)
                    }
                }
            } catch {
                gate.cancel(); mode = .error; status = error.localizedDescription
            }
        }
    }
    func stop() {
        guard mode == .recording, let id = currentID else { return }
        ticker?.invalidate(); ticker = nil
        do {
            let audio = try capture.stop()
            guard gate.finishRecording(id) else { return }
            pendingAudio = audio
            transcribe(audio, id: id)
        } catch {
            gate.cancel(); mode = .error; status = error.localizedDescription
        }
    }
    private func transcribe(_ audio: Data, id: UUID) {
        mode = .transcribing; status = "Turning speech into text…"; level = 0
        let endpoint = AppSettings.endpoint, token = TokenStore.read()
        let language = AppSettings.language, vocabulary = AppSettings.vocabulary
        requestTask = Task {
            do {
                let reply = try await TranscriptionClient.transcribe(audio: audio, id: id, endpoint: endpoint,
                                                                     token: token, language: language, vocabulary: vocabulary)
                guard !Task.isCancelled, gate.acceptResult(id) else { return }
                let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    mode = .error; status = "No speech was detected. Try again closer to the microphone."; return
                }
                transcript = text
                let outcome = await TextInsertion.insert(text, target: target, captureIssue: captureIssue)
                guard !Task.isCancelled, currentID == id else { return }
                status = outcome; mode = .ready; pendingAudio = nil
                let item = Transcript(id: id, date: Date(), text: text, target: target?.name ?? "Clipboard")
                history.insert(item, at: 0); history = Array(history.prefix(50))
                if saveHistory {
                    do { try HistoryStore.save(history) }
                    catch { settingsMessage = "Could not save local history: \(error.localizedDescription)" }
                }
            } catch {
                guard !Task.isCancelled, currentID == id else { return }
                gate.cancel(); mode = .error; status = error.localizedDescription
            }
        }
    }
    func retry() {
        guard let audio = pendingAudio, !busy else { return }
        gate.cancel(); let id = UUID()
        guard gate.begin(id), gate.finishRecording(id) else { return }
        currentID = id
        // A delayed retry always returns text for review; never pastes at an old cursor.
        target = nil; captureIssue = "retries return text for review. Use Copy to paste it."
        transcribe(audio, id: id)
    }
    func cancel() {
        if mode == .testingInsertion {
            // A diagnostic test must not discard audio retained for a failed dictation's retry.
            requestTask?.cancel(); requestTask = nil
            mode = .ready; status = "Insertion test cancelled"; settingsMessage = status
            return
        }
        requestTask?.cancel(); requestTask = nil
        capture.cancel(); ticker?.invalidate(); ticker = nil
        gate.cancel(); currentID = nil; pendingAudio = nil; target = nil
        mode = .idle; status = "Cancelled"; level = 0; meter.reset()
    }
    func testInsertion() {
        guard !busy else { return }
        refreshPermissions()
        let destination = TextInsertion.capture(previousApp: lastExternalApp)
        guard let target = destination.target else {
            settingsMessage = destination.issue ?? "Select a text field in another app first."
            return
        }
        mode = .testingInsertion; status = "Testing automatic insertion…"
        settingsMessage = "Inserting “ClearFlow insertion test.” into " + target.name
        requestTask = Task {
            let outcome = await TextInsertion.insert("ClearFlow insertion test.", target: target)
            guard !Task.isCancelled else { return }
            status = outcome; settingsMessage = outcome; mode = .ready
        }
    }
    func copy(_ text: String? = nil) {
        let text = text ?? transcript
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Copied to clipboard"
    }
    func saveSettings() {
        guard let url = Endpoint.validated(endpoint) else { settingsMessage = "Enter an HTTPS service address, or HTTP on localhost, without a query or password."; return }
        guard vocabulary.utf16.count <= 1000 else { settingsMessage = "Keep vocabulary under 1,000 characters."; return }
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lang.isEmpty || lang.range(of: "^[a-z]{2,3}$", options: .regularExpression) != nil else {
            settingsMessage = "Use a language code such as en, es or fr, or leave blank for auto-detect."; return
        }
        do {
            if !token.isEmpty { try TokenStore.save(token); token = "" }
            guard !TokenStore.read().isEmpty else { settingsMessage = "Enter your private service token."; return }
            AppSettings.endpoint = url.absoluteString; endpoint = url.absoluteString
            AppSettings.language = lang; language = lang
            AppSettings.vocabulary = vocabulary; AppSettings.saveHistory = saveHistory
            if saveHistory { try HistoryStore.save(history) } else { try HistoryStore.clear() }
            hasToken = true; settingsMessage = "Saved. Your access token is in macOS Keychain."
        } catch { settingsMessage = error.localizedDescription }
    }
    func testConnection() {
        Task {
            settingsMessage = "Checking service…"
            do { settingsMessage = try await TranscriptionClient.health(endpoint: endpoint) + ". Transcription authentication is checked when you dictate." }
            catch { settingsMessage = error.localizedDescription }
        }
    }
    func clearHistory() {
        do { try HistoryStore.clear(); history = []; transcript = ""; status = "History cleared" }
        catch { settingsMessage = error.localizedDescription }
    }
}
