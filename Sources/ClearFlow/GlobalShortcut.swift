import Carbon

@MainActor final class GlobalShortcut {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    func register() -> Bool {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x43464c57 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in shortcut.onPress?() }
            return noErr
        }, 1, &type, pointer, &handler)
        guard status == noErr else { return false }
        let id = EventHotKeyID(signature: 0x43464c57, id: 1)
        return RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey | shiftKey), id, GetApplicationEventTarget(), 0, &reference) == noErr
    }
    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil; handler = nil
    }
}
