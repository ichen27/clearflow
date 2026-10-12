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
        print("PASS: Carbon registration, reapply, conflict preservation, replacement and cleanup")
    }
}
