import Foundation

/// Direct WebSocket client for Smallest AI Waves real-time speech-to-text.
/// Streams raw 16kHz mono 16-bit PCM audio and receives partial/final transcripts.
actor SmallestAIClient {

    // MARK: - Types

    enum ClientError: LocalizedError {
        case noAPIKey
        case connectionFailed(String)
        case sessionNotActive

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "Smallest AI API key not set."
            case .connectionFailed(let msg): return "Connection failed: \(msg)"
            case .sessionNotActive: return "No active transcription session."
            }
        }
    }

    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var isActive = false
    private var segments: [String] = []
    private var lastText = ""
    private var finalizeSent = false

    private var finalContinuation: CheckedContinuation<String, Error>?

    /// Called on the main thread with accumulated transcript text as partials arrive.
    nonisolated let onPartial: @Sendable (String) -> Void

    private static let wssURL = "wss://api.smallest.ai/waves/v1/pulse/get_text"

    // MARK: - Init

    init(onPartial: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onPartial = onPartial
    }

    // MARK: - Session Lifecycle

    /// Opens a WebSocket connection to Smallest AI Waves.
    func startSession(apiKey: String, language: String = "en") throws {
        guard !apiKey.isEmpty else { throw ClientError.noAPIKey }

        segments = []
        lastText = ""
        finalizeSent = false

        var components = URLComponents(string: Self.wssURL)!
        components.queryItems = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.resume()
        webSocketTask = task
        isActive = true

        // Start receive loop
        Task { await receiveLoop() }

        // Start ping keepalive
        Task { await pingLoop() }
    }

    /// Sends a raw PCM audio chunk (binary frame).
    func sendChunk(_ pcm: Data) {
        guard isActive, let task = webSocketTask else { return }
        task.send(.data(pcm)) { _ in }
    }

    /// Signals end of audio and waits for the final transcript.
    /// Returns the complete accumulated transcript.
    func finalize() async throws -> String {
        guard isActive, let task = webSocketTask else {
            throw ClientError.sessionNotActive
        }

        finalizeSent = true

        // Send finalize signal
        let msg = try JSONSerialization.data(withJSONObject: ["type": "finalize"])
        let text = String(data: msg, encoding: .utf8)!
        task.send(.string(text)) { _ in }

        // Wait for final transcript with timeout
        return try await withCheckedThrowingContinuation { continuation in
            self.finalContinuation = continuation

            // 15-second timeout
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if let cont = self.finalContinuation {
                    self.finalContinuation = nil
                    let result = self.lastText.isEmpty ? self.joinSegments(self.segments) : self.lastText
                    cont.resume(returning: result)
                    self.close()
                }
            }
        }
    }

    /// Cancel the session without waiting for a result.
    func cancel() {
        finalContinuation?.resume(returning: "")
        finalContinuation = nil
        close()
    }

    // MARK: - Private

    /// Join segments: space between them, but skip space if next starts with punctuation.
    private func joinSegments(_ segs: [String]) -> String {
        let trimmed = segs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "" }

        var result = trimmed[0]
        for i in 1..<trimmed.count {
            let next = trimmed[i]
            if let first = next.first, ".,;:!?".contains(first) {
                result += next
            } else {
                result += " " + next
            }
        }
        return result
    }

    private func close() {
        isActive = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while isActive {
            do {
                let message = try await task.receive()
                guard case .string(let text) = message,
                      let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                let transcript = json["transcript"] as? String ?? ""
                let isFinal = json["is_final"] as? Bool ?? false
                let isLast = json["is_last"] as? Bool ?? false

                if isFinal && !transcript.isEmpty {
                    // Confirmed segment — accumulate
                    segments.append(transcript)
                    lastText = joinSegments(segments)
                    onPartial(lastText)
                } else if !transcript.isEmpty && !isFinal {
                    // Partial — show accumulated segments + current partial
                    let preview = joinSegments(segments + [transcript])
                    onPartial(preview)
                }

                if isLast || (isFinal && finalizeSent) {
                    let result = lastText.isEmpty ? joinSegments(segments) : lastText
                    if let cont = finalContinuation {
                        finalContinuation = nil
                        cont.resume(returning: result)
                    }
                    close()
                    return
                }
            } catch {
                if let cont = finalContinuation {
                    finalContinuation = nil
                    let result = lastText.isEmpty ? joinSegments(segments) : lastText
                    cont.resume(returning: result)
                }
                close()
                return
            }
        }
    }

    private func pingLoop() async {
        while isActive {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
            webSocketTask?.sendPing { _ in }
        }
    }
}
