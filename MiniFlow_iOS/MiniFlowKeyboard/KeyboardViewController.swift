import UIKit
import SwiftUI
import Combine

class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<VoiceInputView>?
    private var viewModel: KeyboardViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false

        let vm = KeyboardViewModel(textDocumentProxy: textDocumentProxy, inputViewController: self)
        self.viewModel = vm

        let voiceInputView = VoiceInputView(
            viewModel: vm,
            onSwitchKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )

        let hostingController = UIHostingController(rootView: voiceInputView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.heightAnchor.constraint(equalToConstant: 258),
        ])

        self.hostingController = hostingController
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel?.refreshSessionState()
    }
}

// MARK: - FlowSessionManager (duplicated for extension sandbox)

private enum FlowSessionKeys {
    static let isSessionActive = "flow_session_active"
    static let sessionHeartbeat = "flow_session_heartbeat"
    static let recordingCommand = "flow_recording_command"
    static let transcriptionResult = "flow_transcription_result"
    static let recordingStatus = "flow_recording_status"
    static let errorMessage = "flow_error_message"
    static let partialTranscript = "flow_partial_transcript"
}

/// File-based IPC — mirrors the main app's FlowSessionManager.
private class FlowSessionManager {
    static let shared = FlowSessionManager()

    private let appGroupID = "group.com.smallestai.MiniFlow"
    private var containerURL: URL?

    private init() {
        containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private func read(_ key: String) -> String? {
        guard let url = containerURL?.appendingPathComponent(key) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func write(_ value: String, key: String) {
        guard let url = containerURL?.appendingPathComponent(key) else { return }
        try? value.write(to: url, atomically: true, encoding: .utf8)
    }

    var isSessionActive: Bool {
        guard read(FlowSessionKeys.isSessionActive) == "true" else { return false }
        // Check heartbeat freshness
        guard let raw = read(FlowSessionKeys.sessionHeartbeat),
              let heartbeat = Double(raw) else { return false }
        let age = Date().timeIntervalSince1970 - heartbeat
        return age <= 1.5
    }

    var recordingStatus: String {
        read(FlowSessionKeys.recordingStatus) ?? "idle"
    }

    var transcriptionResult: String {
        get { read(FlowSessionKeys.transcriptionResult) ?? "" }
        set { write(newValue, key: FlowSessionKeys.transcriptionResult) }
    }

    var errorMessage: String {
        read(FlowSessionKeys.errorMessage) ?? ""
    }

    var partialTranscript: String {
        read(FlowSessionKeys.partialTranscript) ?? ""
    }

    func setReturnAppBundleID(_ bundleID: String) {
        write(bundleID, key: "flow_return_app_bundle_id")
    }

    func requestStartRecording() {
        write("start", key: FlowSessionKeys.recordingCommand)
    }

    func requestStopRecording() {
        write("stop", key: FlowSessionKeys.recordingCommand)
    }

    func requestCancelRecording() {
        write("cancel", key: FlowSessionKeys.recordingCommand)
    }

    func consumeTranscriptionResult() -> String {
        let result = transcriptionResult
        transcriptionResult = ""
        write("idle", key: FlowSessionKeys.recordingStatus)
        write("", key: FlowSessionKeys.partialTranscript)
        return result
    }
}

// MARK: - KeyboardViewModel

@MainActor
class KeyboardViewModel: ObservableObject {
    @Published var state: KeyboardRecordingState = .idle
    @Published var transcribedText: String = ""
    @Published var partialText: String = ""
    @Published var canUndo = false

    private var lastInsertedText: String = ""
    private let textDocumentProxy: UITextDocumentProxy
    private weak var inputViewController: UIInputViewController?
    private let sessionManager = FlowSessionManager.shared
    private var statusMonitorTimer: Timer?
    private var sessionMonitorTimer: Timer?
    private var sessionTimeoutTask: DispatchWorkItem?

    init(textDocumentProxy: UITextDocumentProxy, inputViewController: UIInputViewController) {
        self.textDocumentProxy = textDocumentProxy
        self.inputViewController = inputViewController
    }

    func refreshSessionState() {
        stopStatusMonitoring()
        if !sessionManager.isSessionActive {
            if state != .idle && state != .needsSession { state = .idle }
        } else {
            let status = sessionManager.recordingStatus
            if status == "idle" || status == "done" || status == "error" {
                state = .idle
            }
            if status == "recording" || status == "processing" {
                startStatusMonitoring()
            }
        }
    }

    func undoLastInsertion() {
        guard canUndo, !lastInsertedText.isEmpty else { return }
        for _ in 0..<lastInsertedText.count { textDocumentProxy.deleteBackward() }
        lastInsertedText = ""
        canUndo = false
    }

    func deleteBackward() { textDocumentProxy.deleteBackward() }
    func insertReturn() { textDocumentProxy.insertText("\n") }

    func clearAll() {
        if let before = textDocumentProxy.documentContextBeforeInput {
            for _ in 0..<before.count { textDocumentProxy.deleteBackward() }
        }
    }

    func toggleRecording() {
        switch state {
        case .idle, .needsSession, .error:
            startRecording()
        case .recording:
            stopRecording()
        case .waitingForSession, .processing, .success:
            break
        }
    }

    func startRecording() {
        canUndo = false
        lastInsertedText = ""

        if !sessionManager.isSessionActive {
            openMainAppToStartFlow()
            return
        }

        sessionManager.requestStartRecording()
        state = .recording
        startStatusMonitoring()
    }

    func stopRecording() {
        sessionManager.requestStopRecording()
        state = .processing
    }

    func cancelRecording() {
        stopStatusMonitoring()
        sessionManager.requestCancelRecording()
        partialText = ""
        state = .idle
    }

    // MARK: - App Launch

    private func openMainAppToStartFlow() {
        if let bid = getHostAppBundleID() {
            sessionManager.setReturnAppBundleID(bid)
        }

        openURL(URL(string: "miniflow://startflow")!)

        state = .waitingForSession
        startSessionMonitoring()
    }

    private func safeValue(forKey key: String, on obj: NSObject) -> String? {
        let sel = NSSelectorFromString(key)
        guard obj.responds(to: sel) else { return nil }
        return obj.perform(sel)?.takeUnretainedValue() as? String
    }

    private func getHostAppBundleID() -> String? {
        let keys = [
            ["_", "host", "Bundle", "ID"].joined(),
            ["_", "host", "Bundle", "Identifier"].joined(),
            "hostBundleID",
            "hostBundleIdentifier",
        ]

        // Responder chain
        var responder: UIResponder? = inputViewController
        while let r = responder {
            let obj = r as NSObject
            for key in keys {
                if let bid = safeValue(forKey: key, on: obj),
                   !bid.isEmpty, !bid.contains("MiniFlow") {
                    return bid
                }
            }
            responder = r.next
        }

        // Parent VC
        if let parent = inputViewController?.parent as? NSObject {
            for key in keys {
                if let bid = safeValue(forKey: key, on: parent),
                   !bid.isEmpty, !bid.contains("MiniFlow") {
                    return bid
                }
            }
        }

        return nil
    }

    private func openURL(_ url: URL) {
        guard let appClass = NSClassFromString("UIApplication") as? NSObject.Type else { return }
        let sharedSel = NSSelectorFromString("sharedApplication")
        guard appClass.responds(to: sharedSel),
              let app = appClass.perform(sharedSel)?.takeUnretainedValue() else { return }

        typealias OpenMethod = @convention(c) (AnyObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any], ((Bool) -> Void)?) -> Void
        let openSel = NSSelectorFromString("openURL:options:completionHandler:")
        guard let method = class_getInstanceMethod(type(of: app), openSel) else { return }
        let impl = method_getImplementation(method)
        let open = unsafeBitCast(impl, to: OpenMethod.self)
        open(app, openSel, url, [:], nil)
    }

    // MARK: - Monitoring

    private func startSessionMonitoring() {
        sessionMonitorTimer?.invalidate()
        sessionTimeoutTask?.cancel()

        sessionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.sessionManager.isSessionActive {
                    self.sessionMonitorTimer?.invalidate()
                    self.sessionMonitorTimer = nil
                    self.sessionTimeoutTask?.cancel()
                    self.state = .idle
                }
            }
        }

        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.state == .waitingForSession else { return }
                self.sessionMonitorTimer?.invalidate()
                self.sessionMonitorTimer = nil
                self.state = .idle
            }
        }
        sessionTimeoutTask = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    private func startStatusMonitoring() {
        statusMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkStatus() }
        }
    }

    private func stopStatusMonitoring() {
        statusMonitorTimer?.invalidate()
        statusMonitorTimer = nil
    }

    private func checkStatus() {
        if !sessionManager.isSessionActive {
            stopStatusMonitoring()
            state = .needsSession
            openMainAppToStartFlow()
            return
        }

        // Update partial transcript for live display
        let partial = sessionManager.partialTranscript
        if !partial.isEmpty { partialText = partial }

        let status = sessionManager.recordingStatus

        switch status {
        case "recording":
            if state != .recording { state = .recording }
        case "processing":
            if state != .processing { state = .processing }
        case "done":
            stopStatusMonitoring()
            let result = sessionManager.consumeTranscriptionResult()
            if !result.isEmpty {
                let needsSpace: Bool
                if let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty {
                    needsSpace = !before.last!.isWhitespace
                } else {
                    needsSpace = false
                }
                let textToInsert = needsSpace ? " " + result : result
                textDocumentProxy.insertText(textToInsert)
                lastInsertedText = textToInsert
                canUndo = true
                partialText = ""

                state = .success
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.state = .idle
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    self?.canUndo = false
                }
            } else {
                state = .idle
            }
        case "error":
            stopStatusMonitoring()
            let msg = sessionManager.errorMessage
            state = .error(msg.isEmpty ? "Unknown error" : msg)
            partialText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.state = .idle
            }
        default:
            break
        }
    }
}

// MARK: - State

enum KeyboardRecordingState: Equatable {
    case idle, needsSession, waitingForSession, recording, processing, success, error(String)
}
