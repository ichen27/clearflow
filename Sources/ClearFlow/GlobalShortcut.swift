import Carbon
import AppKit
import ClearFlowCore

@MainActor final class GlobalShortcut {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: Shortcut?
    private var generation: UInt32 = 0
    private var fnGlobalMonitor: Any?
    private var fnLocalMonitor: Any?
    private var fnTap = FnTap()
    var onPress: (() -> Void)?
    // Register the replacement first: a conflict must never discard the working shortcut.
    func register(_ value: Shortcut) -> Bool {
        guard value.isValid else { return false }
        if value.isFn { return registerFn() }
        if current == value, reference != nil { return true }
        guard installHandler() else { return false }
        var modifiers: UInt32 = 0
        if value.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if value.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if value.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if value.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        let next = generation &+ 1
        var candidate: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x43464c57, id: next)
        guard RegisterEventHotKey(value.keyCode, modifiers, id, GetApplicationEventTarget(), 0, &candidate) == noErr else { return false }
        if let reference { UnregisterEventHotKey(reference) }
        removeFnMonitors()
        reference = candidate; current = value; generation = next
        return true
    }
    private func registerFn() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        if current == .fn, fnGlobalMonitor != nil, fnLocalMonitor != nil { return true }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .systemDefined]
        guard let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleFn(event)
        }) else { return false }
        guard let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleFn(event)
            return event
        }) else { NSEvent.removeMonitor(global); return false }
        unregister()
        fnGlobalMonitor = global; fnLocalMonitor = local
        current = .fn; generation &+= 1
        return true
    }
    private func handleFn(_ event: NSEvent) {
        guard current == .fn else { return }
        // Only state is inspected. Typed characters are never read, stored or transmitted.
        if event.type == .keyDown || event.type == .systemDefined { fnTap.cancelChord(); return }
        let others = !event.modifierFlags.intersection([.control, .option, .shift, .command]).isEmpty
        if fnTap.flagsChanged(keyCode: event.keyCode, fnDown: event.modifierFlags.contains(.function), otherModifiers: others) {
            let expectedGeneration = generation
            Task { @MainActor [weak self] in
                guard let self, self.current == .fn, self.generation == expectedGeneration else { return }
                self.onPress?()
            }
        }
    }
    private func removeFnMonitors() {
        if let fnGlobalMonitor { NSEvent.removeMonitor(fnGlobalMonitor) }
        if let fnLocalMonitor { NSEvent.removeMonitor(fnLocalMonitor) }
        fnGlobalMonitor = nil; fnLocalMonitor = nil; fnTap = FnTap()
    }
    private func installHandler() -> Bool {
        if handler != nil { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x43464c57 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            let receivedID = id.id
            Task { @MainActor in
                guard shortcut.reference != nil, shortcut.generation == receivedID else { return }
                shortcut.onPress?()
            }
            return noErr
        }, 1, &type, pointer, &handler)
        return status == noErr
    }
    func unregister() {
        removeFnMonitors()
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil; handler = nil; current = nil
    }
}
