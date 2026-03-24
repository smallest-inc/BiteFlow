import Foundation
import Combine
import AVFoundation
import AppKit
import ApplicationServices

@MainActor
final class AgentViewModel: ObservableObject {

    @Published var isListening = false
    @Published var isProcessing = false
    @Published var transcript = ""
    @Published var actions: [ActionResult] = []
    @Published var errorMessage: String?
    @Published var needsAccessibility = false

    @Published var history: [HistoryEntry] = []
    @Published var userName = ""

    @Published var lastResultAction: ActionResult?
    @Published var totalWordsTranscribed: Int = 0
    @Published var averageWpm: Int = 0

    private let api = APIClient.shared
    private let events = EventStream.shared
    private let audio = AudioCaptureService.shared
    private var cancellables = Set<AnyCancellable>()
    private var historyTimer: Timer?
    private var accessibilityTimer: Timer?
    private var targetBundleID: String?
    private var listeningStartTime: Date?
    private var keyReleaseTime: Date?
    private var lastAudioLengthSecs: Double = 0
    private var lastSttMs: Int = 0

    init() {
        Task {
            await checkAccessibility()
            await loadUserName()
            await loadHistory()
        }

        startHistoryPolling()
        startAccessibilityPolling()

        events.$agentStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.isProcessing = (status == "processing")
            }
            .store(in: &cancellables)

        events.$lastActionResult
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] result in
                let ar = ActionResult(action: result.action, success: result.success, message: result.message)
                self?.actions.insert(ar, at: 0)
                self?.lastResultAction = ar
            }
            .store(in: &cancellables)
    }

    deinit {
        historyTimer?.invalidate()
        accessibilityTimer?.invalidate()
    }

    // MARK: - History

    func loadHistory() async {
        if let entries: [HistoryEntry] = try? await api.invoke("get_history") {
            history = entries
            recomputeStats()
        }
    }

    private func recomputeStats() {
        // Seed from history if the UserDefaults key has never been written
        if UserDefaults.standard.object(forKey: "mf_total_words_ever") == nil && !history.isEmpty {
            let historyCount = history.reduce(0) { acc, entry in
                acc + entry.transcript.split(separator: " ").count
            }
            UserDefaults.standard.set(historyCount, forKey: "mf_total_words_ever")
        }
        totalWordsTranscribed = UserDefaults.standard.integer(forKey: "mf_total_words_ever")
        let totalSeconds = UserDefaults.standard.double(forKey: "mf_total_speaking_seconds")
        if totalSeconds > 0 && totalWordsTranscribed > 0 {
            averageWpm = Int(Double(totalWordsTranscribed) / totalSeconds * 60.0)
        }
    }

    func loadUserName() async {
        if let name: String = try? await api.invoke("get_user_name") {
            userName = name
        }
    }

    private func startHistoryPolling() {
        historyTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.loadHistory() }
        }
    }

    // MARK: - Audio

    func startListening(targetApp: String? = nil) async {
        guard !isListening else { return }
        isListening = true
        targetBundleID = targetApp
        transcript = ""
        errorMessage = nil
        lastResultAction = nil
        listeningStartTime = Date()

        let granted = await audio.requestPermission()
        guard granted else {
            isListening = false
            errorMessage = "Microphone access denied. Enable it in System Settings → Privacy → Microphone."
            return
        }

        // Engine may still be decompressing (PyInstaller onefile) — retry for up to 15s
        var engineReady = false
        for attempt in 1...15 {
            if await api.isBackendAlive() { engineReady = true; break }
            if attempt == 1 { errorMessage = "Starting engine…" }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        errorMessage = nil
        guard engineReady else {
            isListening = false
            errorMessage = "MiniFlow engine failed to start. Try relaunching the app."
            return
        }

        do {
            try audio.startCapture()
        } catch {
            isListening = false
            errorMessage = error.localizedDescription
        }
    }

    func stopListening() async {
        guard isListening else { return }
        isListening = false
        keyReleaseTime = Date()

        let wavData = audio.stopCaptureAndGetWav()
        guard !wavData.isEmpty else { return }

        if let start = listeningStartTime, let release = keyReleaseTime {
            lastAudioLengthSecs = release.timeIntervalSince(start)
        }

        do {
            var body: [String: Any] = ["audio": wavData.base64EncodedString()]
            if let bundleID = targetBundleID { body["bundleID"] = bundleID }
            let sttStart = Date()
            let result: [String: String] = try await api.invoke("transcribe_audio", body: body)
            lastSttMs = Int(Date().timeIntervalSince(sttStart) * 1000)
            let fullText = (result["transcript"] ?? "").trimmingCharacters(in: .whitespaces)
            transcript = fullText
            if !fullText.isEmpty {
                // Accumulate word count (never resets on Clear All)
                let wordCount = fullText.split(separator: " ").count
                let prevWords = UserDefaults.standard.integer(forKey: "mf_total_words_ever")
                UserDefaults.standard.set(prevWords + wordCount, forKey: "mf_total_words_ever")
                totalWordsTranscribed = prevWords + wordCount

                // Accumulate speaking time for WPM calculation
                if let start = listeningStartTime {
                    let duration = max(Date().timeIntervalSince(start), 1.0)
                    let prev = UserDefaults.standard.double(forKey: "mf_total_speaking_seconds")
                    UserDefaults.standard.set(prev + duration, forKey: "mf_total_speaking_seconds")
                }
                await executeCommand(fullText)
            }
            listeningStartTime = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Command execution

    func executeCommand(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let results: [ActionResult] = try await api.invoke("execute_command", body: ["command": text])
            actions = results + actions
            lastResultAction = results.first
            await handleLocalDictationIfNeeded(results)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearActions() {
        actions = []
        transcript = ""
        errorMessage = nil
        lastResultAction = nil
    }

    // MARK: - Accessibility
    // test

    func checkAccessibility() async {
        let trusted = AXIsProcessTrusted()
        axLog("checkAccessibility: trusted=\(trusted)")
        needsAccessibility = !trusted
        if !trusted {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }

    func openAccessibilitySettings() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityPolling() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if self.needsAccessibility && trusted {
                    axLog("Accessibility granted (detected by poll)")
                    self.needsAccessibility = false
                    if self.errorMessage?.contains("Accessibility") == true
                        || self.errorMessage?.contains("clipboard") == true {
                        self.errorMessage = nil
                    }
                } else if !self.needsAccessibility && !trusted {
                    axLog("Accessibility revoked (detected by poll)")
                    self.needsAccessibility = true
                }
            }
        }
    }

    // MARK: - Local typing

    private func handleLocalDictationIfNeeded(_ results: [ActionResult]) async {
        guard let dictation = results.first(where: { $0.action == "dictation" && $0.success }) else {
            return
        }

        let text = dictation.message
        guard !text.isEmpty else { return }

        let trusted = AXIsProcessTrusted()
        axLog("handleLocalDictation: trusted=\(trusted), text='\(String(text.prefix(60)))'")

        if trusted {
            needsAccessibility = false

            // Determine which app to type into
            let bundleID = targetBundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let ownBundleID = Bundle.main.bundleIdentifier

            // Don't type into MiniFlow itself — fall back to clipboard
            if bundleID == ownBundleID {
                copyToClipboard(text)
                axLog("handleLocalDictation: MiniFlow is frontmost, copied to clipboard")
                errorMessage = "Text copied to clipboard (⌘V to paste) — switch to your app first."
                return
            }

            if let bundleID {
                activateTargetApp(bundleID)
                // Wait for the app to come to front — poll until it's frontmost or timeout
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { break }
                }
            }

            await typeTextLocally(text)
            let totalMs = keyReleaseTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
            axLog("""
            ┌─ LATENCY SUMMARY ──────────────────────────
            │  Audio length   : \(String(format: "%.2f", lastAudioLengthSecs))s
            │  STT (Smallest) : \(lastSttMs)ms
            │  Fn release → screen : \(totalMs)ms
            └────────────────────────────────────────────
            """)
            axLog("handleLocalDictation: typed via CGEvent")
            return
        }

        // Accessibility not granted — copy text to clipboard as fallback
        copyToClipboard(text)
        axLog("handleLocalDictation: no accessibility, copied to clipboard")

        needsAccessibility = true
        errorMessage = "Text copied to clipboard (⌘V to paste). Enable Accessibility for auto-typing."
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func activateTargetApp(_ bundleID: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        apps.first?.activate(options: [.activateIgnoringOtherApps])
    }

    private func typeTextLocally(_ text: String) async {
        guard !text.isEmpty else { return }

        // Try AXUIElement first — inserts text directly at cursor, handles newlines natively
        if insertTextViaAX(text) {
            axLog("typeTextLocally: inserted via AXUIElement (\(text.count) chars)")
            return
        }

        // Fallback: clipboard paste via Cmd+V
        axLog("typeTextLocally: AX failed, falling back to Cmd+V")
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if let source = CGEventSource(stateID: .hidSystemState),
           let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
           let up   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            down.flags = .maskCommand
            up.flags   = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        pasteboard.clearContents()
        if let previous { pasteboard.setString(previous, forType: .string) }
    }

    private func insertTextViaAX(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return false
        }
        let element = focusedElement as! AXUIElement
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

}

// MARK: - Diagnostics

private func axLog(_ message: String) {
    let ts = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                          formatOptions: [.withTime, .withColonSeparatorInTime])
    let line = "[\(ts) Swift/AX] \(message)\n"
    NSLog("MiniFlow AX: %@", message)
    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("miniflow/miniflow.log")
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        handle.closeFile()
    }
}

