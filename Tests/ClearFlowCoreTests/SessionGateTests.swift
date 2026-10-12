import Foundation
import ClearFlowCore

var failures = 0
func XCTAssertTrue(_ v: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) { if !v() { failures += 1; print("FAIL \(line): expected true. \(message)") } }
func XCTAssertFalse(_ v: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) { XCTAssertTrue(!v(), message, file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) { XCTAssertTrue(a == b, "Values differ", file: file, line: line) }
func XCTAssertNil<T>(_ a: T?, file: String = #file, line: Int = #line) { XCTAssertTrue(a == nil, "Expected nil", file: file, line: line) }
func XCTAssertNotNil<T>(_ a: T?, file: String = #file, line: Int = #line) { XCTAssertTrue(a != nil, "Expected value", file: file, line: line) }

final class SessionGateTests {
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
  tests.testShortcutRejectsTypingKeysAndMalformedSavedValues()
  tests.testOnlyFinalResultForCurrentRecordingCanComplete()
  tests.testCancelledRequestCannotOverwriteNewDictation()
  tests.testEndpointRejectsCredentialAndQueryLeakage()
  tests.testClipboardMustWaitForObservedInsertion()
  tests.testMeterTracksActualInputAndReturnsToSilence()
  tests.testDestinationUsesLiveFocusAndReportsPermissionFirst()
  if failures > 0 { print("\(failures) failures"); exit(1) }
  print("PASS: session lifecycle, cancellation/stale result, duplicate result, endpoint validation")
 }
}
