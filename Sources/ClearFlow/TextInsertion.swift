import AppKit
import ApplicationServices
import ClearFlowCore

struct InsertionTarget {
    let pid: pid_t
    let name: String
    let element: AXUIElement
    let originalValue: String?
    let range: CFRange?
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
    static func capture(previousApp: NSRunningApplication?) -> InsertionCapture {
        let trusted = AXIsProcessTrusted()
        let pid = DestinationPolicy.pid(frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                        previous: previousApp?.processIdentifier,
                                        own: ProcessInfo.processInfo.processIdentifier)
        // Permission is checked before AX queries so its failure cannot masquerade as missing focus.
        let element = trusted ? pid.flatMap { focusedElement(pid: $0) } : nil
        let isSecure = element.map { secure($0) } ?? false
        let role = element.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? ""
        let editable = ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
        if let issue = DestinationPolicy.failure(accessibility: trusted, hasApp: pid != nil,
                                                hasField: element != nil, secure: isSecure, editable: editable) {
            return InsertionCapture(target: nil, issue: issue)
        }
        guard let pid, let element else { return InsertionCapture(target: nil, issue: "No insertion destination.") }
        return InsertionCapture(target: InsertionTarget(pid: pid,
            name: NSRunningApplication(processIdentifier: pid)?.localizedName ?? "your app", element: element,
            originalValue: attribute(element, kAXValueAttribute) as? String, range: selectedRange(element)), issue: nil)
    }
    static func insert(_ text: String, target: InsertionTarget?, captureIssue: String? = nil) async -> String {
        let outcome = await attemptInsertion(text, target: target, captureIssue: captureIssue)
        // Keep the destination app in front. A rejected insertion still leaves usable
        // text for an ordinary user-initiated paste, without opening the hub.
        guard !Task.isCancelled, outcome.hasPrefix("Ready to copy — ") else { return outcome }
        let board = NSPasteboard.general
        let oldItems = board.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            board.clearContents()
            if !oldItems.isEmpty { board.writeObjects(oldItems) }
            return outcome
        }
        return outcome.replacingOccurrences(of: "Ready to copy — ", with: "Copied to clipboard — ", options: .anchored)
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
            try? await Task.sleep(for: .milliseconds(180))
        }
        guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
              let focused = focusedElement(pid: target.pid), CFEqual(focused, target.element), !secure(focused)
        else { return "Ready to copy — focus changed, so nothing was inserted." }
        if let original = target.originalValue,
           (attribute(focused, kAXValueAttribute) as? String) != original {
            return "Ready to copy — the text field changed while you spoke."
        }
        if let old = target.range {
            guard let current = selectedRange(focused), old.location == current.location, old.length == current.length else {
                return "Ready to copy — the cursor moved while you spoke."
            }
        }
        guard target.range != nil, target.originalValue != nil else {
            return "Ready to copy — this app does not expose enough cursor information for automatic insertion."
        }
        var expected: String?
        if let value = target.originalValue, let range = target.range,
           range.location >= 0, range.length >= 0,
           range.location + range.length <= (value as NSString).length {
            expected = (value as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: text)
        }
        // A no-op replacement already has the desired content; don't enqueue a paste.
        if expected == target.originalValue { return "Inserted into \(target.name) — text already matched." }
        // Some editors report a successful AXSelectedText write without inserting
        // anything. Use the editor's normal paste action instead of that silent no-op.
        guard !Task.isCancelled else { return "Cancelled — transcript kept." }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        else { return "Ready to copy — macOS could not create the paste event." }
        let board = NSPasteboard.general
        let oldItems = board.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            board.clearContents(); if !oldItems.isEmpty { board.writeObjects(oldItems) }
            return "Ready to copy — clipboard was unavailable."
        }
        let ownedChange = board.changeCount
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(500))
        let verified = expected != nil && (attribute(focused, kAXValueAttribute) as? String) == expected
        if PasteRestoration.allowed(expected: expected, observed: attribute(focused, kAXValueAttribute) as? String,
                                    clipboardUnchanged: board.changeCount == ownedChange) {
            board.clearContents()
            if !oldItems.isEmpty { board.writeObjects(oldItems) }
        }
        return verified ? "Inserted into \(target.name)" : "Paste sent to \(target.name) — check the destination. Transcript remains on the clipboard."
    }
}
