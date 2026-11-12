import Foundation
import ClearFlowCore

var failures = 0
func XCTAssertTrue(_ v: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) { if !v() { failures += 1; print("FAIL \(line): expected true. \(message)") } }
func XCTAssertFalse(_ v: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) { XCTAssertTrue(!v(), message, file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) { XCTAssertTrue(a == b, "Values differ", file: file, line: line) }
func XCTAssertNil<T>(_ a: T?, file: String = #file, line: Int = #line) { XCTAssertTrue(a == nil, "Expected nil", file: file, line: line) }
func XCTAssertNotNil<T>(_ a: T?, file: String = #file, line: Int = #line) { XCTAssertTrue(a != nil, "Expected value", file: file, line: line) }

final class SessionGateTests {
    func testFnTapFiresOnceOnReleaseAndIgnoresChords() {
        XCTAssertTrue(Shortcut.fn.isValid)
        XCTAssertEqual(Shortcut.load(Shortcut.fn.encoded), .fn)
        XCTAssertEqual(Shortcut.fn.display, "Fn")
        var held = FnTap(heldAtStart: true)
        XCTAssertTrue(held.isPressed)
        XCTAssertFalse(held.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
        XCTAssertFalse(held.isPressed)
        _ = held.flagsChanged(keyCode: 63, fnDown: true, otherModifiers: false)
        XCTAssertTrue(held.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
        var tap = FnTap()
        XCTAssertFalse(tap.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
        XCTAssertFalse(tap.flagsChanged(keyCode: 63, fnDown: true, otherModifiers: false))
        XCTAssertFalse(tap.flagsChanged(keyCode: 63, fnDown: true, otherModifiers: false))
        XCTAssertTrue(tap.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
        XCTAssertFalse(tap.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
        _ = tap.flagsChanged(keyCode: 63, fnDown: true, otherModifiers: false)
        tap.cancelChord()
        XCTAssertFalse(tap.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
        _ = tap.flagsChanged(keyCode: 63, fnDown: true, otherModifiers: false)
        _ = tap.flagsChanged(keyCode: 56, fnDown: true, otherModifiers: true)
        _ = tap.flagsChanged(keyCode: 56, fnDown: true, otherModifiers: false)
        XCTAssertFalse(tap.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
        _ = tap.flagsChanged(keyCode: 63, fnDown: true, otherModifiers: false)
        _ = tap.flagsChanged(keyCode: 57, fnDown: true, otherModifiers: false)
        XCTAssertFalse(tap.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
        // Arrow/function-key events can carry the function flag without a physical Fn tap.
        XCTAssertFalse(tap.flagsChanged(keyCode: 123, fnDown: true, otherModifiers: false))
        XCTAssertFalse(tap.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
        _ = tap.flagsChanged(keyCode: 63, fnDown: true, otherModifiers: true)
        XCTAssertFalse(tap.flagsChanged(keyCode: 63, fnDown: false, otherModifiers: false))
    }
    func testShortcutRejectsTypingKeysAndMalformedSavedValues() {
        XCTAssertFalse(Shortcut(keyCode: 0, modifiers: []).isValid)
        XCTAssertFalse(Shortcut(keyCode: 0, modifiers: [.shift]).isValid)
        XCTAssertFalse(Shortcut(keyCode: 999, modifiers: [.option]).isValid)
        XCTAssertFalse(Shortcut(keyCode: 49, modifiers: .init(rawValue: 128)).isValid)
        XCTAssertTrue(Shortcut(keyCode: 49, modifiers: [.control, .option]).isValid)
        XCTAssertEqual(Shortcut.load(Data("{}".utf8)), .default)
        XCTAssertEqual(Shortcut.load(Data("{\"keyCode\":0,\"modifiers\":0}".utf8)), .default)
        let chosen = Shortcut(keyCode: 40, modifiers: [.control, .shift])
        XCTAssertEqual(Shortcut.load(chosen.encoded), chosen)
        XCTAssertEqual(chosen.display, "⌃ ⇧ K")
    }
    func testOnlyFinalResultForCurrentRecordingCanComplete() {
        var gate = SessionGate()
        let id = UUID()
        XCTAssertTrue(gate.begin(id))
        XCTAssertFalse(gate.acceptResult(id), "A result must not insert before stop")
        XCTAssertFalse(gate.begin(UUID()), "Cannot overlap recordings")
        XCTAssertTrue(gate.finishRecording(id))
        XCTAssertFalse(gate.acceptResult(UUID()), "Foreign result must not insert")
        XCTAssertTrue(gate.acceptResult(id))
        XCTAssertFalse(gate.acceptResult(id), "Duplicate final must never insert twice")
    }
    func testCancelledRequestCannotOverwriteNewDictation() {
        var gate = SessionGate()
        let old = UUID(), current = UUID()
        XCTAssertTrue(gate.begin(old))
        XCTAssertTrue(gate.finishRecording(old))
        gate.cancel()
        XCTAssertTrue(gate.begin(current))
        XCTAssertFalse(gate.finishRecording(old))
        XCTAssertFalse(gate.acceptResult(old))
        XCTAssertEqual(gate.phase, .recording(current))
        XCTAssertTrue(gate.finishRecording(current))
        XCTAssertTrue(gate.acceptResult(current))
    }
    func testMeterTracksActualInputAndReturnsToSilence() {
        var meter = MeterHistory()
        XCTAssertEqual(meter.samples.count, 10)
        XCTAssertTrue(meter.samples.allSatisfy { $0 == 0 })
        meter.append(1)
        XCTAssertTrue(meter.samples.last! > 0.5, "Speech must produce a visible attack")
        XCTAssertEqual(meter.samples.first, 0)
        for _ in 0..<40 { meter.append(0) }
        XCTAssertTrue(meter.samples.allSatisfy { $0 == 0 }, "Silence must settle into dots, not decorative motion")
        meter.append(.nan); meter.append(.infinity); meter.append(-3)
        XCTAssertTrue(meter.samples.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        meter.append(1); meter.reset()
        XCTAssertTrue(meter.samples.allSatisfy { $0 == 0 })
    }
    func testDestinationUsesLiveFocusAndReportsPermissionFirst() {
        XCTAssertEqual(DestinationPolicy.pid(frontmost: 44, previous: 33, own: 22), 44)
        XCTAssertEqual(DestinationPolicy.pid(frontmost: 22, previous: 33, own: 22), 33)
        XCTAssertNil(DestinationPolicy.pid(frontmost: 22, previous: 22, own: 22))
        XCTAssertEqual(DestinationPolicy.failure(accessibility: false, hasApp: true, hasField: false, secure: false, editable: false),
                       "Enable Accessibility for ClearFlow in System Settings to insert text automatically.")
        XCTAssertNotNil(DestinationPolicy.failure(accessibility: true, hasApp: true, hasField: true, secure: true, editable: true))
        XCTAssertNil(DestinationPolicy.failure(accessibility: true, hasApp: true, hasField: true, secure: false, editable: true))
    }
    func testClipboardMustWaitForObservedInsertion() {
        XCTAssertFalse(PasteRestoration.allowed(expected: "hello", observed: "", clipboardUnchanged: true), "Cancelled or slow paste must keep the transcript available")
        XCTAssertFalse(PasteRestoration.allowed(expected: nil, observed: nil, clipboardUnchanged: true), "Unreadable field cannot prove paste completed")
        XCTAssertFalse(PasteRestoration.allowed(expected: "hello", observed: "hello", clipboardUnchanged: false), "Never replace a newer user copy")
        XCTAssertTrue(PasteRestoration.allowed(expected: "hello", observed: "hello", clipboardUnchanged: true))
    }
    func testEditableFieldsIncludeWebAndCustomEditors() {
        XCTAssertTrue(Editability.allows(role: "AXTextArea", insideEditableContent: false, exposesTextSelection: false, valueSettable: false))
        XCTAssertTrue(Editability.allows(role: "AXGroup", insideEditableContent: true, exposesTextSelection: false, valueSettable: false),
                      "contenteditable web editors report an editable ancestor")
        XCTAssertTrue(Editability.allows(role: "AXUnknown", insideEditableContent: false, exposesTextSelection: true, valueSettable: true))
        XCTAssertFalse(Editability.allows(role: "AXSlider", insideEditableContent: false, exposesTextSelection: false, valueSettable: true),
                       "a settable non-text value is not a cursor")
        XCTAssertFalse(Editability.allows(role: "AXButton", insideEditableContent: false, exposesTextSelection: false, valueSettable: false))
    }
    func testPastePredictionUsesTheCursorAtPasteTime() {
        XCTAssertEqual(PastePrediction.result(of: "big ", in: "a dog", location: 2, length: 0), "a big dog")
        XCTAssertEqual(PastePrediction.result(of: "cat", in: "a dog", location: 2, length: 3), "a cat")
        XCTAssertEqual(PastePrediction.result(of: "é", in: "👍", location: 2, length: 0), "👍é")
        XCTAssertNil(PastePrediction.result(of: "x", in: "abc", location: 2, length: 5))
        XCTAssertNil(PastePrediction.result(of: "x", in: nil, location: 0, length: 0))
        XCTAssertNil(PastePrediction.result(of: "x", in: "abc", location: nil, length: nil))
    }
    func testCleanupRemovesDisfluenciesWithoutRewording() {
        func check(_ raw: String, _ expected: String, line: Int = #line) {
            let actual = TranscriptCleanup.clean(raw)
            XCTAssertTrue(actual == expected, "\(raw.debugDescription) -> \(actual.debugDescription), expected \(expected.debugDescription)", line: line)
        }
        check("Hey, um, can you send me the notes from yesterday's meeting? I think we need to, uh, review the budget before Friday.",
              "Hey can you send me the notes from yesterday's meeting? I think we need to review the budget before Friday.")
        check("Um, so we should ship it.", "So we should ship it.")
        check("Okay. Uh, so the plan works.", "Okay. So the plan works.")
        check("That's it, um.", "That's it.")
        check("Okay. Um. Next step.", "Okay. Next step.")
        check("I I think the the plan is fine.", "I think the plan is fine.")
        check("I know that that is true and I had had enough. It's very very good.",
              "I know that that is true and I had had enough. It's very very good.")
        check("  Extra   spaces , here .  ", "Extra spaces, here.")
        check("Dear Sam, new line, thanks for the update. New paragraph. See you soon.",
              "Dear Sam,\nThanks for the update.\n\nSee you soon.")
        check("We need a new line of products.", "We need a new line of products.")
        check("Version 3.5 costs $4.99 at 3 p.m. on the U.S. site, e.g. today.",
              "Version 3.5 costs $4.99 at 3 p.m. on the U.S. site, e.g. today.")
        check("Summary, umbrella and humble words stay.", "Summary, umbrella and humble words stay.")
        check("Um", "")
    }
    func testCleanupFitsTextAroundTheCursor() {
        XCTAssertEqual(TranscriptCleanup.fit("Hello there.", before: "", after: ""), "Hello there.")
        XCTAssertEqual(TranscriptCleanup.fit("Next point.", before: "Done.", after: ""), " Next point.")
        XCTAssertEqual(TranscriptCleanup.fit("Next point.", before: "Done. ", after: ""), "Next point.")
        XCTAssertEqual(TranscriptCleanup.fit("The big one.", before: "I want", after: ""), " the big one.")
        XCTAssertEqual(TranscriptCleanup.fit("Really big.", before: "a ", after: "dog"), "really big ")
        XCTAssertEqual(TranscriptCleanup.fit("I think so.", before: "and", after: ""), " I think so.")
        XCTAssertEqual(TranscriptCleanup.fit("I'm in.", before: "and", after: ""), " I'm in.")
        XCTAssertEqual(TranscriptCleanup.fit("NASA launched.", before: "and", after: ""), " NASA launched.")
        XCTAssertEqual(TranscriptCleanup.fit("Hello.", before: "(", after: ")"), "Hello.")
        XCTAssertEqual(TranscriptCleanup.fit("Line one.\nLine two.", before: "Intro", after: ""), " Line one.\nLine two.")
    }
    func testEndpointRejectsCredentialAndQueryLeakage() {
        XCTAssertEqual(Endpoint.validated("https://example.workers.dev/")?.absoluteString, "https://example.workers.dev")
        XCTAssertNil(Endpoint.validated("http://public.example"))
        XCTAssertNil(Endpoint.validated("https://user:secret@example.com"))
        XCTAssertNil(Endpoint.validated("https://example.com?token=secret"))
        XCTAssertNil(Endpoint.validated("https://example.com#secret"))
        XCTAssertNil(Endpoint.validated("not a URL"))
        XCTAssertNotNil(Endpoint.validated("http://127.0.0.1:8787"))
    }
}

@main enum CoreChecks {
 static func main() {
  let tests = SessionGateTests()
  tests.testFnTapFiresOnceOnReleaseAndIgnoresChords()
  tests.testShortcutRejectsTypingKeysAndMalformedSavedValues()
  tests.testOnlyFinalResultForCurrentRecordingCanComplete()
  tests.testCancelledRequestCannotOverwriteNewDictation()
  tests.testEndpointRejectsCredentialAndQueryLeakage()
  tests.testClipboardMustWaitForObservedInsertion()
  tests.testMeterTracksActualInputAndReturnsToSilence()
  tests.testDestinationUsesLiveFocusAndReportsPermissionFirst()
  tests.testEditableFieldsIncludeWebAndCustomEditors()
  tests.testPastePredictionUsesTheCursorAtPasteTime()
  tests.testCleanupRemovesDisfluenciesWithoutRewording()
  tests.testCleanupFitsTextAroundTheCursor()
  if failures > 0 { print("\(failures) failures"); exit(1) }
  print("PASS: session lifecycle, cancellation/stale result, duplicate result, endpoint validation")
 }
}
