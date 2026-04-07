import Foundation

/// IPC keys — used as filenames in the shared App Group container.
enum FlowSessionKeys {
    static let isSessionActive = "flow_session_active"
    static let sessionHeartbeat = "flow_session_heartbeat"
    static let recordingCommand = "flow_recording_command"
    static let transcriptionResult = "flow_transcription_result"
    static let recordingStatus = "flow_recording_status"
    static let errorMessage = "flow_error_message"
    static let partialTranscript = "flow_partial_transcript"
}

enum RecordingCommand: String {
    case none, start, stop, cancel
}

enum FlowRecordingStatus: String {
    case idle, recording, processing, done, error
}

/// File-based IPC through the App Group shared container.
/// UserDefaults is unreliable between app and extension on device,
/// so we read/write small text files instead.
class FlowSessionManager {
    static let shared = FlowSessionManager()

    private let appGroupID = "group.com.smallestai.MiniFlow"
    private var containerURL: URL?
    private var heartbeatTimer: Timer?

    private init() {
        containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        if containerURL == nil {
            print("[FlowSession] ERROR: App Group container not accessible: \(appGroupID)")
        } else {
            print("[FlowSession] Container: \(containerURL!.path)")
        }
    }

    // MARK: - File helpers

    private func write(_ value: String, forKey key: String) {
        guard let url = containerURL?.appendingPathComponent(key) else { return }
        try? value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(forKey key: String) -> String? {
        guard let url = containerURL?.appendingPathComponent(key) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func remove(forKey key: String) {
        guard let url = containerURL?.appendingPathComponent(key) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Heartbeat (Main App Only)

    func startHeartbeat() {
        heartbeatTimer?.invalidate()
        updateHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateHeartbeat()
        }
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func updateHeartbeat() {
        write(String(Date().timeIntervalSince1970), forKey: FlowSessionKeys.sessionHeartbeat)
    }

    // MARK: - Session State

    var isSessionActive: Bool {
        get { read(forKey: FlowSessionKeys.isSessionActive) == "true" }
        set { write(newValue ? "true" : "false", forKey: FlowSessionKeys.isSessionActive) }
    }

    func startSession() {
        isSessionActive = true
        recordingCommand = .none
        recordingStatus = .idle
        transcriptionResult = ""
        errorMessage = ""
        partialTranscript = ""
        startHeartbeat()
    }

    func endSession() {
        stopHeartbeat()
        isSessionActive = false
        recordingCommand = .none
        recordingStatus = .idle
    }

    // MARK: - Recording Commands (Keyboard -> App)

    var recordingCommand: RecordingCommand {
        get { RecordingCommand(rawValue: read(forKey: FlowSessionKeys.recordingCommand) ?? "none") ?? .none }
        set { write(newValue.rawValue, forKey: FlowSessionKeys.recordingCommand) }
    }

    func requestStartRecording() { recordingCommand = .start }
    func requestStopRecording() { recordingCommand = .stop }
    func clearCommand() { recordingCommand = .none }

    // MARK: - Recording Status (App -> Keyboard)

    var recordingStatus: FlowRecordingStatus {
        get { FlowRecordingStatus(rawValue: read(forKey: FlowSessionKeys.recordingStatus) ?? "idle") ?? .idle }
        set { write(newValue.rawValue, forKey: FlowSessionKeys.recordingStatus) }
    }

    var transcriptionResult: String {
        get { read(forKey: FlowSessionKeys.transcriptionResult) ?? "" }
        set { write(newValue, forKey: FlowSessionKeys.transcriptionResult) }
    }

    var errorMessage: String {
        get { read(forKey: FlowSessionKeys.errorMessage) ?? "" }
        set { write(newValue, forKey: FlowSessionKeys.errorMessage) }
    }

    var partialTranscript: String {
        get { read(forKey: FlowSessionKeys.partialTranscript) ?? "" }
        set { write(newValue, forKey: FlowSessionKeys.partialTranscript) }
    }

    // MARK: - Return App

    var returnAppBundleID: String? {
        get { read(forKey: "flow_return_app_bundle_id") }
        set {
            if let v = newValue { write(v, forKey: "flow_return_app_bundle_id") }
            else { remove(forKey: "flow_return_app_bundle_id") }
        }
    }

    // MARK: - Convenience

    func consumeTranscriptionResult() -> String {
        let result = transcriptionResult
        transcriptionResult = ""
        partialTranscript = ""
        recordingStatus = .idle
        return result
    }
}
