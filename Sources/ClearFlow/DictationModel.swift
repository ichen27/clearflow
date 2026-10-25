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
    @Published var recordingNotice = ""
    @Published private(set) var recoverableRecordings: [URL] = []
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
    @Published private(set) var shortcut = AppSettings.shortcut
    @Published var shortcutMessage = ""
    private var recordingShortcut = false
    var suspendShortcut: (() -> Void)?
    func beginShortcutRecording() {
        guard !busy else { return }
        recordingShortcut = true
        suspendShortcut?()
    }
    func endShortcutRecording() {
        guard recordingShortcut else { return }
        recordingShortcut = false
        shortcutAvailable = registerShortcut?(shortcut) ?? false
    }
    var registerShortcut: ((Shortcut) -> Bool)?
    func changeShortcut(_ value: Shortcut) -> String? {
        guard !busy else { return "Finish or cancel dictation before changing the shortcut." }
        guard value.isValid else { return "Tap Fn alone, or include Control, Option, or Command with a key." }
        if value.isFn && !AXIsProcessTrusted() {
            suspendShortcut?()
            AppSettings.shortcut = value; shortcut = value; shortcutAvailable = false
            return nil // Save the selection; visibly report the permission needed to activate it.
        }
        guard let registerShortcut, registerShortcut(value) else {
            return "This shortcut is unavailable or used by another app."
        }
        AppSettings.shortcut = value
        shortcut = value; shortcutAvailable = true
        return nil
    }
    var showWindow: (() -> Void)?
    var lastExternalApp: NSRunningApplication?
    private var demoMode = false
    private let capture: AudioCapture
    private let recoveryDirectory: URL
    // Injection seams exercise the actual stop/save/insertion ordering without microphone access.
    var transcribeRecording: ((URL, UUID) async throws -> TranscriptionReply)?
    var insertTranscript: ((String) async -> String)?
    var persistHistory: ([Transcript]) throws -> Void = { try HistoryStore.save($0) }
    private var interrupted = false
    private var diskCheckAt = 0.0
    private var gate = SessionGate()
    private var currentID: UUID?
    private var target: InsertionTarget?
    private var captureIssue: String?
    private var pendingAudio: RecordedAudio?
    private var ticker: Timer?
    private var requestTask: Task<Void, Never>?
    private var workspaceObserver: NSObjectProtocol?
    var busy: Bool { mode == .recording || mode == .transcribing || mode == .requestingPermission || mode == .testingInsertion }
    var canRetry: Bool { pendingAudio != nil && !busy }
    init(demo: Bool = false, capture: AudioCapture? = nil, recoveryDirectory: URL = RecordingStore.directory) {
        let capture = capture ?? AudioCapture()
        self.capture = capture
        self.recoveryDirectory = recoveryDirectory
        capture.onUnexpectedStop = { [weak self] message in self?.recordingInterrupted(message) }
        if demo {
            demoMode = true
            shortcut = .default
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
        refreshRecoveries()
        if let file = recoverableRecordings.first {
            pendingAudio = RecordedAudio(url: file)
            mode = .error
            recordingNotice = "An unfinished recording is saved on this Mac. Open ClearFlow and choose Recover."
            status = recordingNotice
        }
    }
    func refreshRecoveries() {
        do { recoverableRecordings = try RecordingStore.recordings(in: recoveryDirectory) }
        catch { recordingNotice = "Could not read saved recordings: " + error.localizedDescription }
    }
    func recover(_ url: URL) {
        guard !busy, recoverableRecordings.contains(url) else { return }
        pendingAudio = RecordedAudio(url: url)
        retry()
    }
    func discardRecovery(_ url: URL) {
        guard !busy, recoverableRecordings.contains(url) else { return }
        do {
            try RecordedAudio(url: url).discard()
            if pendingAudio?.url == url { pendingAudio = nil }
            refreshRecoveries()
            status = "Recording discarded"
        } catch { recordingNotice = "Could not delete the recording: " + error.localizedDescription }
    }
    func recordingInterrupted(_ message: String) {
        guard mode == .recording else { return }
        interrupted = true
        // Show a nonactivating warning throughout transcription and until explicitly dismissed.
        recordingNotice = message + " Saving the available speech…"
        target = nil; captureIssue = nil
        stop()
    }
    func prepareForQuit() {
        requestTask?.cancel(); requestTask = nil
        ticker?.invalidate(); ticker = nil
        if mode == .recording { pendingAudio = try? capture.stop() }
        gate.cancel(); currentID = nil
        // Keep durable audio for the next launch. Quitting is not a discard action.
    }
    func refreshPermissions() {
        guard !demoMode else { return }
        hasAccessibility = AXIsProcessTrusted()
        if shortcut.isFn {
            if !hasAccessibility { suspendShortcut?(); shortcutAvailable = false }
            else if !shortcutAvailable { shortcutAvailable = registerShortcut?(shortcut) ?? false }
        }
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
        guard !recordingShortcut else { return }
        switch mode {
        case .recording: stop()
        case .transcribing, .requestingPermission, .testingInsertion: cancel()
        default: start()
        }
    }
    func start() {
        guard !busy, !recordingShortcut else { return }
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
        interrupted = false
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
            beginCapture()
        }
    }
    func beginCapture() {
        guard mode != .recording, mode != .transcribing else { return }
        interrupted = false
        do {
            gate.cancel()
            let id = UUID()
            guard gate.begin(id) else { return }
            currentID = id
            try capture.start()
            seconds = 0; level = 0; meter.reset(); diskCheckAt = 0
            mode = .recording; status = "Listening"
            ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.mode == .recording else { return }
                    self.seconds = self.capture.seconds; self.level = self.capture.level
                    self.meter.append(self.level)
                    if self.seconds >= self.diskCheckAt {
                        self.diskCheckAt = self.seconds + 5
                        if let free = try? FileManager.default.attributesOfFileSystem(forPath: self.recoveryDirectory.path)[.systemFreeSize] as? NSNumber,
                           free.int64Value < 100 * 1024 * 1024 {
                            self.recordingNotice = "Storage is almost full. Finish dictation now to save your words before recording fails."
                        }
                    }
                }
            }
        } catch {
            gate.cancel(); mode = .error; status = error.localizedDescription
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
            refreshRecoveries()
            recordingNotice = "Recording ended: " + status + " Check saved recordings in ClearFlow."
        }
    }
    private func transcribe(_ audio: RecordedAudio, id: UUID) {
        mode = .transcribing; status = "Turning speech into text…"; level = 0
        let endpoint = AppSettings.endpoint, token = transcribeRecording == nil ? TokenStore.read() : ""
        let language = AppSettings.language, vocabulary = AppSettings.vocabulary
        requestTask = Task {
            do {
                let reply: TranscriptionReply
                if let transcribeRecording { reply = try await transcribeRecording(audio.url, id) }
                else { reply = try await TranscriptionClient.transcribe(file: audio.url, id: id, endpoint: endpoint,
                                                                     token: token, language: language, vocabulary: vocabulary,
                                                                     progress: { [weak self] part, count in
                    await self?.transcriptionProgress(part: part, count: count, id: id)
                }) }
                guard !Task.isCancelled, gate.acceptResult(id) else { return }
                let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    mode = .error; status = "No speech was detected. Audio saved for recovery."
                    recordingNotice = status; refreshRecoveries(); return
                }
                transcript = text
                let transcriptID = UUID(uuidString: audio.url.deletingPathExtension().lastPathComponent) ?? id
                let item = Transcript(id: transcriptID, date: Date(), text: text, target: interrupted ? "Interrupted recording" : target?.name ?? "Clipboard")
                history.removeAll { $0.id == transcriptID }
                history.insert(item, at: 0)
                // Commit words to disk BEFORE any asynchronous insertion or clipboard operation.
                if saveHistory {
                    do { try persistHistory(history) }
                    catch {
                        mode = .error
                        status = "Transcript could not be saved. Audio is retained for recovery. " + error.localizedDescription
                        recordingNotice = status
                        refreshRecoveries()
                        return
                    }
                }
                let outcome: String
                if interrupted { outcome = saveHistory ? "Recovered transcript saved in Recent Dictations." : "Recovered transcript is available for this session; audio retained." }
                else if let insertTranscript { outcome = await insertTranscript(text) }
                else { outcome = await TextInsertion.insert(text, target: target, captureIssue: captureIssue) }
                guard !Task.isCancelled, currentID == id else { return }
                status = outcome; mode = .ready
                // History-off is an explicit privacy choice; retain interrupted audio until discarded.
                if saveHistory || !interrupted {
                    do { try audio.discard(); pendingAudio = nil }
                    catch { recordingNotice = "Transcript is ready, but the saved audio could not be removed." }
                }
                if interrupted { recordingNotice = outcome }
                refreshRecoveries()
            } catch {
                guard !Task.isCancelled, currentID == id else { return }
                gate.cancel(); mode = .error; status = error.localizedDescription
                recordingNotice = "Transcription failed. Your recording is saved on this Mac. Open ClearFlow to retry. " + status
                refreshRecoveries()
            }
        }
    }
    private func transcriptionProgress(part: Int, count: Int, id: UUID) {
        guard currentID == id, mode == .transcribing else { return }
        status = count > 1 ? "Transcribing part \(part) of \(count)…" : "Turning speech into text…"
    }
    func retry() {
        guard let audio = pendingAudio, !busy else { return }
        gate.cancel(); let id = UUID()
        guard gate.begin(id), gate.finishRecording(id) else { return }
        currentID = id
        // A delayed retry always returns text for review; never pastes at an old cursor.
        interrupted = true
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
        if mode == .transcribing {
            requestTask?.cancel(); requestTask = nil
            gate.cancel(); currentID = nil
            mode = .error; level = 0
            status = "Transcription paused. Audio saved for recovery."
            recordingNotice = status
            refreshRecoveries()
            return
        }
        requestTask?.cancel(); requestTask = nil
        capture.cancel(); ticker?.invalidate(); ticker = nil
        gate.cancel(); currentID = nil; pendingAudio = nil; target = nil
        mode = .idle; status = "Cancelled"; level = 0; meter.reset()
        refreshRecoveries()
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
