import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var flowRecorder: FlowBackgroundRecorder

    @State private var apiKey = ""
    @State private var keySaved = false
    @State private var micGranted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Session status card
                    sessionCard

                    // API Key
                    apiKeySection

                    // Keyboard setup instructions
                    keyboardInstructions

                    // Mic permission
                    micPermissionSection
                }
                .padding(20)
            }
            .navigationTitle("MiniFlow")
            .background(Color(UIColor.systemGroupedBackground))
        }
        .task {
            apiKey = KeychainHelper.smallestAPIKey ?? ""
            micGranted = AVAudioApplication.shared.recordPermission == .granted
        }
    }

    // MARK: - Session Card

    private var sessionCard: some View {
        VStack(spacing: 16) {
            Image(systemName: flowRecorder.isSessionActive ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 48))
                .foregroundStyle(flowRecorder.isSessionActive ? .green : .secondary)

            Text(flowRecorder.isSessionActive ? "Session Active" : "Session Inactive")
                .font(.headline)

            if flowRecorder.isRecording {
                Text("Recording...")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            Button {
                if flowRecorder.isSessionActive {
                    flowRecorder.endFlowSession()
                } else {
                    flowRecorder.startFlowSession()
                }
            } label: {
                Text(flowRecorder.isSessionActive ? "End Session" : "Start Session")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(flowRecorder.isSessionActive ? Color.red : Color(hex: "2D6B5E"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - API Key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Smallest AI API Key")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                SecureField("sk_...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))

                Button {
                    KeychainHelper.smallestAPIKey = apiKey
                    keySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
                } label: {
                    Text(keySaved ? "Saved" : "Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(apiKey.isEmpty ? Color.gray : Color(hex: "2D6B5E"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(apiKey.isEmpty)
            }

            Text("Get your key from app.smallest.ai")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Keyboard Instructions

    private var keyboardInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Enable Keyboard", systemImage: "keyboard")
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Settings → General → Keyboard → Keyboards")
                instructionRow(number: "2", text: "Add New Keyboard → MiniFlow")
                instructionRow(number: "3", text: "Tap MiniFlow → Enable \"Allow Full Access\"")
                instructionRow(number: "4", text: "Switch to MiniFlow keyboard in any app")
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color(hex: "2D6B5E"))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Mic Permission

    private var micPermissionSection: some View {
        HStack {
            Image(systemName: micGranted ? "checkmark.circle.fill" : "mic.slash")
                .foregroundStyle(micGranted ? .green : .orange)
            Text(micGranted ? "Microphone access granted" : "Microphone access needed")
                .font(.system(size: 13))
            Spacer()
            if !micGranted {
                Button("Grant") {
                    Task {
                        micGranted = await AVAudioApplication.requestRecordPermission()
                    }
                }
                .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Color+Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
