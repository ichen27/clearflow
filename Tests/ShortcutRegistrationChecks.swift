import AppKit
import Carbon
import ClearFlowCore

// Device integration check: exercises Carbon ownership without synthesizing keypresses.
@main enum ShortcutRegistrationChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let shortcut = GlobalShortcut()
        defer { shortcut.unregister() }
        let first = Shortcut(keyCode: 98, modifiers: [.control, .option, .shift, .command])
        let second = Shortcut(keyCode: 100, modifiers: [.control, .option, .shift, .command])
        func require(_ condition: Bool, _ message: String) {
            if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        func reserve(_ key: UInt32) -> EventHotKeyRef? {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(key, UInt32(controlKey | optionKey | shiftKey | cmdKey),
                EventHotKeyID(signature: 0x54455354, id: key), GetApplicationEventTarget(), 0, &ref)
            return result == noErr ? ref : nil
        }
        require(shortcut.register(first), "initial registration")
        require(shortcut.register(first), "reapplying the current shortcut")
        if !AXIsProcessTrusted() {
            require(!shortcut.register(.fn), "Fn must not report active without Accessibility")
            let old = reserve(first.keyCode)
            if let old { UnregisterEventHotKey(old) }
            require(old == nil, "permission failure must preserve the Carbon binding")
        }
        guard let conflict = reserve(second.keyCode) else { fatalError("Test combination already occupied") }
        require(!shortcut.register(second), "conflicting shortcut must be rejected")
        let stolen = reserve(first.keyCode)
        if let stolen { UnregisterEventHotKey(stolen) }
        require(stolen == nil, "failed change must preserve the first shortcut")
        UnregisterEventHotKey(conflict)
        require(shortcut.register(second), "retry after conflict is released")
        let released = reserve(first.keyCode)
        require(released != nil, "successful replacement must release the old shortcut")
        if let released { UnregisterEventHotKey(released) }
        shortcut.unregister()
        let final = reserve(second.keyCode)
        require(final != nil, "unregister must release the current shortcut")
        if let final { UnregisterEventHotKey(final) }
        let recorder = ShortcutRecorderButton(frame: NSRect(x: 0, y: 0, width: 160, height: 32))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(recorder)
        var chosen = first
        recorder.onBegin = { shortcut.unregister() }
        recorder.onEnd = { require(shortcut.register(chosen), "restore shortcut after recording") }
        recorder.onCapture = { value in
            guard shortcut.register(value) else { return "Conflict" }
            chosen = value; return nil
        }
        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!
        }
        recorder.performClick(nil)
        require(recorder.isRecording, "click starts recording")
        recorder.keyDown(with: key(0))
        require(recorder.isRecording && chosen == first, "plain typing key must not overwrite shortcut")
        recorder.keyDown(with: key(100, [.control, .option, .shift, .command, .capsLock]))
        require(!recorder.isRecording && chosen == second, "keypress saves combination and ignores Caps Lock")
        recorder.performClick(nil)
        recorder.keyDown(with: key(53))
        require(!recorder.isRecording && chosen == second, "Escape cancels without changes")
        recorder.performClick(nil)
        _ = recorder.resignFirstResponder()
        require(!recorder.isRecording && chosen == second, "losing focus cancels capture")
        recorder.performClick(nil)
        guard let occupied = reserve(first.keyCode) else { fatalError("Test key unexpectedly occupied") }
        recorder.keyDown(with: key(98, [.control, .option, .shift, .command]))
        require(recorder.isRecording && chosen == second, "conflict keeps recorder active without saving")
        recorder.keyDown(with: key(53))
        let previous = reserve(second.keyCode)
        if let previous { UnregisterEventHotKey(previous) }
        require(previous == nil, "cancel after conflict restores previous shortcut")
        UnregisterEventHotKey(occupied)
        recorder.performClick(nil)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        require(!recorder.isRecording, "leaving window cancels recording")
        shortcut.unregister()
        // Exercise Fn recorder flags directly without posting any events to other apps.
        recorder.onCapture = { value in chosen = value; return nil }
        recorder.onEnd = nil
        recorder.performClick(nil)
        func fnEvent(_ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: 63)!
        }
        recorder.flagsChanged(with: fnEvent(.function))
        require(recorder.isRecording, "Fn down must wait for release")
        recorder.flagsChanged(with: fnEvent([]))
        require(!recorder.isRecording && chosen == .fn, "Fn release saves Fn alone")
        recorder.performClick(nil)
        recorder.flagsChanged(with: fnEvent(.function))
        recorder.keyDown(with: key(0, [.function, .control]))
        recorder.flagsChanged(with: fnEvent([]))
        require(recorder.isRecording && chosen == .fn, "Fn chord cannot be captured as another shortcut")
        recorder.cancelRecording()
        print("PASS: shortcut recorder key capture, invalid input, Escape and focus loss")
        print("PASS: Carbon registration, reapply, conflict preservation, replacement and cleanup")
    }
}
