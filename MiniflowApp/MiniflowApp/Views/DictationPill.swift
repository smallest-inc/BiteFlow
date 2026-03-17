import SwiftUI

/// 280×56pt floating pill shown at screen bottom-center during Fn-key dictation.
/// Hosted in a separate nonactivating FloatingPanel managed by AppDelegate.
struct DictationPill: View {
    @ObservedObject var vm: AgentViewModel

    var body: some View {
        HStack(spacing: 12) {
            stateIcon
                .frame(width: 28, height: 28)
            stateLabel
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(width: 280, height: 56)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 5)
    }

    // MARK: - State Icon

    @ViewBuilder
    private var stateIcon: some View {
        if vm.isListening {
            WaveformBars()
        } else if let result = vm.lastResultAction {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(result.success ? .green : .red)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - State Label

    @ViewBuilder
    private var stateLabel: some View {
        if vm.isListening {
            Text("Listening…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black)
                .transition(.opacity)
        } else if let result = vm.lastResultAction {
            Text(result.message)
                .font(.system(size: 13))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .transition(.opacity)
        } else {
            Text("Hold Fn to dictate")
                .font(.system(size: 13))
                .foregroundStyle(Color.black)
        }
    }
}

// MARK: - Animated Waveform Bars

private struct WaveformBars: View {
    @State private var animating = false
    private let barHeights: [CGFloat] = [8, 14, 20, 14, 18, 10, 16]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(barHeights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    .frame(width: 3, height: animating ? barHeights[i] : barHeights[i] * 0.35)
                    .animation(
                        .easeInOut(duration: 0.38 + Double(i) * 0.06)
                            .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
