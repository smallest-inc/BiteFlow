import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var pillPanel: FloatingPanel?

    private var agentVM: AgentViewModel!
    private var statusCancellable: AnyCancellable?
    private var pillCancellable: AnyCancellable?
    private var pillHideTask: Task<Void, Never>?

    // Subprocess handle for the bundled Python engine
    private var engineProcess: Process?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launchEngineIfBundled()
        agentVM = AgentViewModel()
        setupStatusItem()
        setupMainWindow()
        setupDictationPill()
        setupHotkey()
        setupMenuBarStatusObserver()
        setupPillVisibilityObserver()
        EventStream.shared.connect()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
        EventStream.shared.disconnect()
        engineProcess?.terminate()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "waveform.circle.fill",
                               accessibilityDescription: "MiniFlow")
        button.image?.isTemplate = true
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show MiniFlow",
                                  action: #selector(toggleMainWindow),
                                  keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit MiniFlow",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        return menu
    }

    private func setupMenuBarStatusObserver() {
        statusCancellable = EventStream.shared.$agentStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                let name = status == "processing"
                    ? "waveform.circle"
                    : "waveform.circle.fill"
                self?.statusItem.button?.image = NSImage(
                    systemSymbolName: name,
                    accessibilityDescription: "MiniFlow"
                )
                self?.statusItem.button?.image?.isTemplate = true
            }
    }

    // MARK: - Main Window

    private func setupMainWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "MiniFlow"
        win.contentView = NSHostingView(rootView: MainWindowView(vm: agentVM))
        win.center()
        win.isReleasedWhenClosed = false
        mainWindow = win
    }

    @objc func toggleMainWindow() {
        guard let win = mainWindow else { return }
        if win.isVisible {
            win.orderOut(nil)
        } else {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Dictation Pill

    private func setupDictationPill() {
        guard let screen = NSScreen.main else { return }
        let pillW: CGFloat = 280
        let pillH: CGFloat = 56
        let x = screen.frame.midX - pillW / 2
        let y = screen.frame.minY + 40

        let panel = FloatingPanel(
            contentRect: NSRect(x: x, y: y, width: pillW, height: pillH),
            styleMask: .nonactivatingPanel,
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: DictationPill(vm: agentVM))
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        pillPanel = panel
    }

    private func setupPillVisibilityObserver() {
        pillCancellable = agentVM.$isListening
            .receive(on: RunLoop.main)
            .sink { [weak self] isListening in
                guard let self else { return }
                if isListening {
                    self.pillHideTask?.cancel()
                    self.pillPanel?.orderFront(nil)
                } else {
                    // Hide immediately when Fn is released.
                    self.pillHideTask?.cancel()
                    self.pillPanel?.orderOut(nil)
                }
            }
    }

    // MARK: - Settings (now a tab in the main window)

    @objc func openSettings() {
        toggleMainWindow()
    }

    // MARK: - Fn Hotkey (hold-to-talk)

    private func setupHotkey() {
        HotkeyManager.shared.onPress = { [weak self] in
            // Capture the frontmost app BEFORE MiniFlow steals focus
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            Task { await self?.agentVM.startListening(targetApp: bundleID) }
        }
        HotkeyManager.shared.onRelease = { [weak self] in
            Task { await self?.agentVM.stopListening() }
        }
        HotkeyManager.shared.register()
    }

    // MARK: - Bundled Engine

    private func launchEngineIfBundled() {
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("miniflow/miniflow.log")
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // onedir layout: Contents/Resources/miniflow-engine/miniflow-engine
        // legacy fallback: Contents/MacOS/miniflow-engine
        let resources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
        let macOS = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS")
        let candidates = [
            resources.appendingPathComponent("miniflow-engine/miniflow-engine"),
            macOS.appendingPathComponent("miniflow-engine/miniflow-engine"),
            macOS.appendingPathComponent("miniflow-engine"),
        ]

        guard let engineURL = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            appendToLog(logURL, "[Swift] ERROR: miniflow-engine binary not found in bundle\n")
            appendToLog(logURL, "[Swift] Searched: \(candidates.map(\.path).joined(separator: ", "))\n")
            return
        }

        appendToLog(logURL, "[Swift] Found engine at: \(engineURL.path)\n")

        // Ensure executable bit is set
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: engineURL.path)

        // Avoid duplicate engine launches when another MiniFlow instance is
        // already listening on localhost:8765.
        if isPortListening(8765) {
            appendToLog(logURL, "[Swift] Engine already listening on :8765, skipping launch\n")
            return
        }

        let process = Process()
        process.executableURL = engineURL

        // Ensure TLS cert env vars are set for GUI-launched flows.
        // This mirrors:
        // launchctl setenv SSL_CERT_FILE ".../cacert.pem"
        // launchctl setenv REQUESTS_CA_BUNDLE ".../cacert.pem"
        let certCandidates = [
            resources.appendingPathComponent("miniflow-engine/_internal/certifi/cacert.pem"),
            resources.appendingPathComponent("miniflow-engine/certifi/cacert.pem"),
        ]
        if let certURL = certCandidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) {
            setLaunchctlEnv(name: "SSL_CERT_FILE", value: certURL.path, logURL: logURL)
            setLaunchctlEnv(name: "REQUESTS_CA_BUNDLE", value: certURL.path, logURL: logURL)

            var env = ProcessInfo.processInfo.environment
            env["SSL_CERT_FILE"] = certURL.path
            env["REQUESTS_CA_BUNDLE"] = certURL.path
            process.environment = env

            appendToLog(logURL, "[Swift] SSL cert env configured: \(certURL.path)\n")
        } else {
            appendToLog(logURL, "[Swift] WARN: certifi cacert.pem not found in bundle\n")
        }

        // Pipe stdout+stderr into the log file
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [logURL] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            appendToLog(logURL, chunk)
        }

        process.terminationHandler = { [logURL] p in
            appendToLog(logURL, "[Swift] Engine exited with code \(p.terminationStatus)\n")
        }

        do {
            try process.run()
            appendToLog(logURL, "[Swift] Engine launched (pid=\(process.processIdentifier))\n")
            engineProcess = process
        } catch {
            appendToLog(logURL, "[Swift] ERROR: Failed to launch engine: \(error)\n")
        }
    }
}

// MARK: - Log helpers (nonisolated, safe to call from any thread)

private func appendToLog(_ url: URL, _ message: String) {
    appendToLog(url, Data(message.utf8))
}

private func appendToLog(_ url: URL, _ data: Data) {
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    } else {
        try? data.write(to: url)
    }
}

private func setLaunchctlEnv(name: String, value: String, logURL: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["setenv", name, value]
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            appendToLog(logURL, "[Swift] launchctl setenv \(name) set\n")
        } else {
            appendToLog(logURL, "[Swift] WARN: launchctl setenv \(name) failed with status \(process.terminationStatus)\n")
        }
    } catch {
        appendToLog(logURL, "[Swift] WARN: launchctl setenv \(name) error: \(error)\n")
    }
}

private func isPortListening(_ port: Int) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return false }
        let output = String(data: data, encoding: .utf8) ?? ""
        // lsof prints a header plus one or more rows when listeners exist.
        return output.split(separator: "\n").count > 1
    } catch {
        return false
    }
}
