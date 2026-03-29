import AVFoundation
import Foundation

final class AudioCaptureService {

    static let shared = AudioCaptureService()

    private let engine = AVAudioEngine()
    private var isRunning = false
    private var accumulatedPCM = Data()

    /// Called with each ~100ms PCM chunk as it's captured (for streaming)
    var onChunk: ((Data) -> Void)?

    private init() {
        // When the user changes audio device (plug/unplug headphones, switch input),
        // AVAudioEngine stops automatically. Restart capture so audio keeps flowing.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.isRunning = false
            self.engine.inputNode.removeTap(onBus: 0)
            try? self.startCapture()
        }
    }

    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    // MARK: - Permission

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Capture lifecycle

    func startCapture() throws {
        guard !isRunning else { return }
        accumulatedPCM = Data()

        let input = engine.inputNode
        let native = input.inputFormat(forBus: 0)
        let bufferSize = AVAudioFrameCount(native.sampleRate * 0.1) // ~100ms at native rate

        input.installTap(onBus: 0, bufferSize: bufferSize, format: native) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, nativeFormat: native)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stopCapture() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    /// Stop capture and return a WAV-encoded Data containing all recorded audio.
    func stopCaptureAndGetWav() -> Data {
        stopCapture()
        return buildWav(from: accumulatedPCM)
    }

    // MARK: - Buffer processing

    private func handle(buffer: AVAudioPCMBuffer, nativeFormat: AVAudioFormat) {
        guard let converted = convert(buffer, from: nativeFormat, to: format) else { return }
        guard let data = pcmData(from: converted) else { return }
        accumulatedPCM.append(data)
        onChunk?(data)
    }

    // MARK: - WAV encoding

    private func buildWav(from pcm: Data) -> Data {
        var wav = Data()
        let pcmSize = UInt32(pcm.count)

        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) }
        }

        // RIFF chunk
        wav.append(contentsOf: "RIFF".utf8)
        appendLE(pcmSize + 36)          // file size minus 8-byte RIFF header
        wav.append(contentsOf: "WAVE".utf8)
        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        appendLE(UInt32(16))            // chunk size
        appendLE(UInt16(1))             // PCM
        appendLE(UInt16(1))             // mono
        appendLE(UInt32(16_000))        // sample rate
        appendLE(UInt32(32_000))        // byte rate (sampleRate * blockAlign)
        appendLE(UInt16(2))             // block align
        appendLE(UInt16(16))            // bits per sample
        // data chunk
        wav.append(contentsOf: "data".utf8)
        appendLE(pcmSize)
        wav.append(pcm)

        return wav
    }

    // MARK: - Helpers

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        from src: AVAudioFormat,
        to dst: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: src, to: dst) else { return nil }
        let ratio = dst.sampleRate / src.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let out = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            consumed = true
            return buffer
        }
        return error == nil ? out : nil
    }

    private func pcmData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else { return nil }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData[0], count: byteCount)
    }
}
