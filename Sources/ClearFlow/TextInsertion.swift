import AppKit
import ApplicationServices
import ClearFlowCore

/// The app that was in front when dictation started. Text is pasted at that app's
/// cursor when the transcript is ready, wherever the cursor is by then.
struct InsertionTarget {
    let pid: pid_t
    let name: String
}
struct InsertionCapture {
    let target: InsertionTarget?
    let issue: String?
}
@MainActor enum TextInsertion {
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    static func focusedElement(pid: pid_t) -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    static func secure(_ element: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<6 {
            if (attribute(current, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole { return true }
            guard let parent = attribute(current, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return false
    }
    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let ref = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(ref, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }
    static func editable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let valueSettable = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
        return Editability.allows(role: attribute(element, kAXRoleAttribute) as? String ?? "",
                                  insideEditableContent: attribute(element, "AXEditableAncestor") != nil,
                                  exposesTextSelection: selectedRange(element) != nil,
                                  valueSettable: valueSettable)
    }
    static func capture(previousApp: NSRunningApplication?) -> InsertionCapture {
        let trusted = AXIsProcessTrusted()
        let pid = DestinationPolicy.pid(frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                        previous: previousApp?.processIdentifier,
                                        own: ProcessInfo.processInfo.processIdentifier)
        guard trusted else {
            return InsertionCapture(target: nil, issue: DestinationPolicy.failure(accessibility: false, hasApp: true,
                                                                                hasField: true, secure: false, editable: true))
        }
        guard let pid else {
            return InsertionCapture(target: nil, issue: DestinationPolicy.failure(accessibility: true, hasApp: false,
                                                                                hasField: true, secure: false, editable: true))
        }
        // The field is checked when the transcript is ready, not now: the cursor may
        // legitimately move, and apps such as web editors rebuild their elements.
        return InsertionCapture(target: InsertionTarget(pid: pid,
            name: NSRunningApplication(processIdentifier: pid)?.localizedName ?? "your app"), issue: nil)
    }
    static func insert(_ text: String, target: InsertionTarget?, captureIssue: String? = nil) async -> String {
        let outcome = await attemptInsertion(text, target: target, captureIssue: captureIssue)
        // Keep the destination app in front. A rejected insertion still leaves usable
        // text for an ordinary user-initiated paste, without opening the hub.
        guard !Task.isCancelled, outcome.hasPrefix("Ready to copy — ") else { return outcome }
        let board = NSPasteboard.general
        let oldItems = snapshot(board)
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            board.clearContents()
            if !oldItems.isEmpty { board.writeObjects(oldItems) }
            return outcome
        }
        return outcome.replacingOccurrences(of: "Ready to copy — ", with: "Copied to clipboard — ", options: .anchored)
    }
    private static func snapshot(_ board: NSPasteboard) -> [NSPasteboardItem] {
        board.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
    }
    /// Polls instead of sleeping a fixed time: fast when the condition is already met,
    /// tolerant when an app is slow to activate or to apply a paste.
    private static func waitUntil(_ timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock(), deadline = clock.now + timeout
        while !condition() {
            if Task.isCancelled || clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return true
    }
    private static func heldModifiers() -> Bool {
        !CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]).isEmpty
    }
    private static func attemptInsertion(_ text: String, target: InsertionTarget?, captureIssue: String?) async -> String {
        guard AXIsProcessTrusted() else {
            return "Ready to copy — enable Accessibility for ClearFlow in System Settings to insert automatically."
        }
        guard let target else { return "Ready to copy — " + (captureIssue ?? "select an editable field before recording.") }
        if Task.isCancelled { return "Cancelled — transcript kept." }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID {
            NSRunningApplication(processIdentifier: target.pid)?.activate()
        }
        let frontmost = await waitUntil(.seconds(1)) {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
        }
        guard !Task.isCancelled else { return "Cancelled — transcript kept." }
        guard frontmost else { return "Ready to copy — you switched away from \(target.name), so nothing was inserted." }
        guard let focused = focusedElement(pid: target.pid) else {
            return "Ready to copy — no text field is focused in \(target.name)."
        }
        guard !secure(focused) else { return "Ready to copy — automatic insertion is disabled in password fields." }
        guard editable(focused) else {
            return "Ready to copy — the focused control in \(target.name) is not an editable text field."
        }
        // A modifier still held from the shortcut would turn Command-V into another command.
        _ = await waitUntil(.milliseconds(1500)) { !heldModifiers() }
        guard !Task.isCancelled else { return "Cancelled — transcript kept." }
        let before = attribute(focused, kAXValueAttribute) as? String
        let range = selectedRange(focused)
        let expected = PastePrediction.result(of: text, in: before,
                                              location: range.map { $0.location }, length: range.map { $0.length })
        if let expected, expected == before { return "Inserted into \(target.name) — text already matched." }
        // Some editors report a successful AXSelectedText write without inserting
        // anything. Use the editor's normal paste action instead of that silent no-op.
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        else { return "Ready to copy — macOS could not create the paste event." }
        let board = NSPasteboard.general
        let oldItems = snapshot(board)
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            board.clearContents(); if !oldItems.isEmpty { board.writeObjects(oldItems) }
            return "Ready to copy — clipboard was unavailable."
        }
        let ownedChange = board.changeCount
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        var verified = false
        if let expected {
            verified = await waitUntil(.milliseconds(750)) { (attribute(focused, kAXValueAttribute) as? String) == expected }
        }
        if PasteRestoration.allowed(expected: expected, observed: attribute(focused, kAXValueAttribute) as? String,
                                    clipboardUnchanged: board.changeCount == ownedChange) {
            board.clearContents()
            if !oldItems.isEmpty { board.writeObjects(oldItems) }
        }
        return verified ? "Inserted into \(target.name)" : "Pasted into \(target.name). The transcript is also on the clipboard."
    }
}
