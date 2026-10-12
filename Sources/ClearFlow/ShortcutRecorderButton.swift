import AppKit
import ClearFlowCore

/// Captures keys only while explicitly focused; never installs a global keyboard monitor.
@MainActor final class ShortcutRecorderButton: NSButton {
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onCapture: ((Shortcut) -> String?)?
    var onMessage: ((String) -> Void)?
    var savedTitle = "" { didSet { if !isRecording { title = savedTitle } } }
    private var mouseMonitor: Any?
    private(set) var isRecording = false
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded; controlSize = .large
        font = .systemFont(ofSize: 14, weight: .medium)
        target = self; action = #selector(beginRecording)
        setAccessibilityLabel("Change shortcut")
        toolTip = "Click, then press your new shortcut. Escape cancels."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func beginRecording() {
        guard isEnabled, !isRecording, window?.makeFirstResponder(self) == true else { return }
        isRecording = true
        title = "Press shortcut…"
        onBegin?()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                self.cancelRecording()
            }
            return event
        }
        onMessage?("Press your shortcut. Escape cancels.")
        NotificationCenter.default.addObserver(self, selector: #selector(cancelRecording),
            name: NSWindow.didResignKeyNotification, object: window)
    }
    @objc func cancelRecording() {
        guard isRecording else { return }
        finishRecording()
        onMessage?("")
    }
    private func finishRecording() {
        isRecording = false
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        title = savedTitle
        onEnd?()
    }
    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelRecording() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.isKeyWindow == true else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        guard !event.isARepeat else { return }
        if event.keyCode == 53 { cancelRecording(); return }
        var modifiers: Shortcut.Modifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        let value = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard value.isValid else {
            onMessage?("Use Control, Option, or Command with a letter, number, Space, or F-key. Escape cancels.")
            return
        }
        guard let onCapture else { cancelRecording(); return }
        if let error = onCapture(value) {
            onMessage?(error + " Try another combination, or press Escape.")
        } else {
            savedTitle = value.display
            finishRecording()
            onMessage?("Shortcut saved.")
        }
    }
}
