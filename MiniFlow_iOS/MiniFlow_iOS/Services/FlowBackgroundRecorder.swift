import Foundation
@preconcurrency import AVFoundation
import UIKit
import Combine

/// Background audio recorder that streams PCM chunks to Smallest AI via WebSocket.
@MainActor
class FlowBackgroundRecorder: ObservableObject {
    static let shared = FlowBackgroundRecorder()

    @Published var isSessionActive = false
    @Published var isRecording = false

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    private var sttClient: SmallestAIClient?
    private var commandMonitorTimer: DispatchSourceTimer?
    private var autoStopTimer: DispatchSourceTimer?
    private let sessionManager = FlowSessionManager.shared

    private static let maxRecordingSeconds: TimeInterval = 60

    private init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSessionActive else { return }
                try? self.audioEngine?.start()
            }
        }
    }

    // MARK: - Session Lifecycle

    func startFlowSession() {
        guard !isSessionActive else { return }
        print("[MiniFlow] Starting Flow Session...")

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP]
            )
            try session.setActive(true)
        } catch {
            print("[MiniFlow] Failed to configure audio session: \(error)")
            return
        }

        guard setupAudioEngine() else {
            print("[MiniFlow] Failed to setup audio engine")
            return
        }

        sessionManager.startSession()
        isSessionActive = true
        startCommandMonitoring()
        print("[MiniFlow] Flow session started")
    }

    func endFlowSession() {
        print("[MiniFlow] Ending Flow Session...")
        stopCommandMonitoring()
        stopAudioEngine()

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        sessionManager.endSession()
        isSessionActive = false
        isRecording = false
        print("[MiniFlow] Flow session ended")
    }

    // MARK: - Audio Engine

    private func setupAudioEngine() -> Bool {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)

        print("[MiniFlow] Native audio: \(nativeFormat.sampleRate)Hz, \(nativeFormat.channelCount)ch")

        let bufferSize = AVAudioFrameCount(nativeFormat.sampleRate * 0.1)

        input.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { [weak self] buffer, _ in
            let pcm = self?.convertToPCM16(buffer: buffer, from: nativeFormat)
            Task { @MainActor [weak self] in
                guard let self, self.isRecording, let pcm else { return }
                self.sendChunk(pcm)
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            inputNode = input
            print("[MiniFlow] Audio engine started")
            return true
        } catch {
            print("[MiniFlow] Failed to start audio engine: \(error)")
            return false
        }
    }

    private func stopAudioEngine() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
    }

    // MARK: - PCM Conversion

    private nonisolated func convertToPCM16(buffer: AVAudioPCMBuffer, from srcFormat: AVAudioFormat) -> Data? {
        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else { return nil }
        let ratio = targetFormat.sampleRate / srcFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard capacity > 0,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            consumed = true
            return buffer
        }

        guard error == nil, let channelData = outBuffer.int16ChannelData else { return nil }
        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData[0], count: byteCount)
    }

    // MARK: - Streaming STT

    private func sendChunk(_ pcm: Data) {
        guard let client = sttClient else { return }
        Task { await client.sendChunk(pcm) }
    }

    // MARK: - Command Monitoring

    private func startCommandMonitoring() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.checkForCommands() }
        }
        timer.resume()
        commandMonitorTimer = timer
    }

    private func stopCommandMonitoring() {
        commandMonitorTimer?.cancel()
        commandMonitorTimer = nil
    }

    private func checkForCommands() {
        let command = sessionManager.recordingCommand
        switch command {
        case .start:
            if !isRecording {
                sessionManager.clearCommand()
                startRecording()
            }
        case .stop:
            if isRecording {
                sessionManager.clearCommand()
                stopRecording()
            }
        case .cancel:
            sessionManager.clearCommand()
            cancelRecording()
        case .none:
            break
        }
    }

    // MARK: - Recording Control

    private func startRecording() {
        guard audioEngine?.isRunning == true else {
            sessionManager.recordingStatus = .error
            sessionManager.errorMessage = "Session expired. Please restart."
            sessionManager.endSession()
            isSessionActive = false
            return
        }

        guard let apiKey = KeychainHelper.smallestAPIKey, !apiKey.isEmpty else {
            sessionManager.recordingStatus = .error
            sessionManager.errorMessage = "API key not set. Open MiniFlow to add your key."
            return
        }

        let client = SmallestAIClient { [weak self] partial in
            Task { @MainActor [weak self] in
                self?.sessionManager.partialTranscript = partial
            }
        }
        sttClient = client

        Task {
            do {
                try await client.startSession(apiKey: apiKey)
                isRecording = true
                sessionManager.recordingStatus = .recording
                sessionManager.partialTranscript = ""
                print("[MiniFlow] Recording started, streaming to Smallest AI")
            } catch {
                sessionManager.recordingStatus = .error
                sessionManager.errorMessage = "Failed to connect: \(error.localizedDescription)"
                sttClient = nil
            }
        }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + Self.maxRecordingSeconds)
        timer.setEventHandler { [weak self] in
            guard let self, self.isRecording else { return }
            print("[MiniFlow] Auto-stopping at \(Int(Self.maxRecordingSeconds))s")
            self.stopRecording()
        }
        timer.resume()
        autoStopTimer = timer
    }

    private func stopRecording() {
        autoStopTimer?.cancel()
        autoStopTimer = nil
        isRecording = false
        sessionManager.recordingStatus = .processing

        guard let client = sttClient else {
            sessionManager.recordingStatus = .error
            sessionManager.errorMessage = "No active STT session"
            return
        }

        Task {
            do {
                let transcript = try await client.finalize()
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    sessionManager.recordingStatus = .error
                    sessionManager.errorMessage = "No speech detected"
                } else {
                    sessionManager.transcriptionResult = trimmed
                    sessionManager.recordingStatus = .done
                }
                print("[MiniFlow] Transcription: \(trimmed)")
            } catch {
                sessionManager.recordingStatus = .error
                sessionManager.errorMessage = "Transcription failed"
                print("[MiniFlow] Transcription error: \(error)")
            }
            sttClient = nil
        }
    }

    private func cancelRecording() {
        autoStopTimer?.cancel()
        autoStopTimer = nil
        isRecording = false
        if let client = sttClient {
            Task { await client.cancel() }
            sttClient = nil
        }
        sessionManager.recordingStatus = .idle
        sessionManager.partialTranscript = ""
        print("[MiniFlow] Recording cancelled")
    }
}
