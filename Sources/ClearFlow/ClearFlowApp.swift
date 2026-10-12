import AppKit
import SwiftUI
import Combine
import ClearFlowCore

@main @MainActor enum ClearFlowMain {
    static func main() {
        let args = CommandLine.arguments
        if args.count == 4 && args[1] == "--render-reveal" {
            guard ["landscape", "portrait"].contains(args[3]) else { fputs("Use landscape or portrait\n", stderr); exit(1) }
            do { try SocialPreview.render(to: URL(fileURLWithPath: args[2]), portrait: args[3] == "portrait") }
            catch { fputs("Reveal rendering failed\n", stderr); exit(1) }
            return
        }
        if args.count == 3 && args[1] == "--render-media" {
            do { try MediaPreview.render(to: URL(fileURLWithPath: args[2])) }
            catch { fputs("Media rendering failed\n", stderr); exit(1) }
            return
        }
        if args.count >= 3 && args[1] == "--configure" {
            guard let endpoint = Endpoint.validated(args[2]) else { fputs("Invalid endpoint\n", stderr); exit(1) }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard token.count >= 32 else { fputs("Provide the private service token on stdin\n", stderr); exit(1) }
            do { try TokenStore.save(token); AppSettings.endpoint = endpoint.absoluteString; print("ClearFlow configured. Token stored in Keychain.") }
            catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if args.count >= 3 && args[1] == "--transcribe-file" {
            let path = args[2], endpoint = AppSettings.endpoint, token = TokenStore.read()
            Task.detached {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    let reply = try await TranscriptionClient.transcribe(audio: data, id: UUID(), endpoint: endpoint,
                                                                       token: token, language: "en", vocabulary: "")
                    print(reply.text); exit(0)
                } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = DictationModel()
    private let shortcut = GlobalShortcut()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var overlay: NSPanel!
    private var subscription: AnyCancellable?
    private var startItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "ClearFlow")
        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: model.status, action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem); menu.addItem(.separator())
        startItem = NSMenuItem(title: "Start dictation", action: #selector(toggle), keyEquivalent: "")
        startItem.target = self; menu.addItem(startItem)
        let open = NSMenuItem(title: "Open ClearFlow…", action: #selector(showWindow), keyEquivalent: "")
        open.target = self; menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ClearFlow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        overlay = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 118, height: 46),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.title = "ClearFlow Dictation"
        overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = true
        overlay.level = .floating; overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.contentView = NSHostingView(rootView: OverlayView(model: model))
        model.showWindow = { [weak self] in self?.showWindow() }
        shortcut.onPress = { [weak self] in self?.model.toggle() }
        model.shortcutAvailable = shortcut.register(model.shortcut)
        model.suspendShortcut = { [weak self] in self?.shortcut.unregister() }
        model.registerShortcut = { [weak self] value in
            guard let self else { return false }
            return self.shortcut.register(value)
        }
        subscription = model.$mode.combineLatest(model.$status, model.$shortcut).sink { [weak self] _, _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
        // Open the controls at launch; recording still requires an explicit action.
        showWindow()
    }
    private func refresh() {
        statusMenuItem.title = String(model.status.prefix(85))
        let action = model.mode == .recording ? "Finish dictation" : model.busy ? "Cancel" : "Start dictation"
        startItem.title = action + "     " + model.shortcut.display
        statusItem.button?.image = NSImage(systemSymbolName: model.mode == .recording ? "mic.fill" : model.mode == .transcribing ? "hourglass" : "waveform",
                                           accessibilityDescription: "ClearFlow")
        if model.busy {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let screen {
                overlay.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - overlay.frame.width / 2, y: screen.visibleFrame.minY + 34))
            }
            overlay.orderFrontRegardless()
        } else { overlay.orderOut(nil) }
    }
    @objc func toggle() { model.toggle() }
    @objc func showWindow() {
        if window == nil {
            let controller = NSHostingController(rootView: MainView(model: model))
            let w = NSWindow(contentViewController: controller)
            w.title = "ClearFlow"; w.setContentSize(NSSize(width: 1120, height: 780))
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.minSize = NSSize(width: 960, height: 680)
            w.isReleasedWhenClosed = false; w.center()
            window = w
        }
        model.refreshPermissions()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        model.cancel(); shortcut.unregister()
    }
}
