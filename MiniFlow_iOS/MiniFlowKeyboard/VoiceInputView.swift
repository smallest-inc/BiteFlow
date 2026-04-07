import SwiftUI

// MARK: - Theme

private enum Theme {
    private static let softSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 0.84)
            : UIColor(white: 1.0, alpha: 0.88)
    }

    static let accent = Color(red: 0.18, green: 0.42, blue: 0.37)     // MiniFlow teal (#2D6B5E)
    static let recording = Color(red: 0.88, green: 0.22, blue: 0.28)
    static let success = Color(red: 0.29, green: 0.71, blue: 0.45)
    static let surface = Color(uiColor: softSurface)
    static let surfaceBorder = Color(uiColor: .separator).opacity(0.16)
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
}

// MARK: - VoiceInputView

struct VoiceInputView: View {
    @ObservedObject var viewModel: KeyboardViewModel
    let onSwitchKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            headerRow
            centerPanel
            bottomControls
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("MiniFlow")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 0)

            statusPill

            Button(action: onSwitchKeyboard) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.surfaceBorder, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch viewModel.state {
        case .recording:
            HStack(spacing: 6) {
                PulseDot(color: Theme.recording)
                Text("Recording")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.recording.opacity(0.2)))
            .overlay(Capsule().stroke(Theme.recording.opacity(0.45), lineWidth: 1))

        case .processing:
            HStack(spacing: 6) {
                ProgressView().tint(Theme.textPrimary).scaleEffect(0.8)
                Text("Processing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().stroke(Theme.surfaceBorder, lineWidth: 1))

        case .waitingForSession:
            HStack(spacing: 6) {
                ProgressView().tint(Theme.textPrimary).scaleEffect(0.8)
                Text("Opening App")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().stroke(Theme.surfaceBorder, lineWidth: 1))

        case .success:
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text("Inserted")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.success.opacity(0.26)))
            .overlay(Capsule().stroke(Theme.success.opacity(0.45), lineWidth: 1))

        case .error:
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Error")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.recording.opacity(0.2)))
            .overlay(Capsule().stroke(Theme.recording.opacity(0.45), lineWidth: 1))

        default:
            EmptyView()
        }
    }

    // MARK: - Center

    private var centerPanel: some View {
        VStack(spacing: 8) {
            recordButton

            switch viewModel.state {
            case .recording:
                if !viewModel.partialText.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                Text(viewModel.partialText)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: true, vertical: false)
                                Color.clear.frame(width: 1, height: 1).id("end")
                            }
                        }
                        .frame(height: 20)
                        .onChange(of: viewModel.partialText) {
                            proxy.scrollTo("end", anchor: .trailing)
                        }
                        .onAppear {
                            proxy.scrollTo("end", anchor: .trailing)
                        }
                    }
                } else {
                    RecorderTicker(color: Theme.recording)
                        .frame(height: 20)
                }
            case .processing:
                ProgressView().tint(Theme.textPrimary).scaleEffect(0.82)
                    .frame(height: 20)
            case .waitingForSession:
                Text("Launching MiniFlow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(height: 20)
            case .error(let message):
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 20)
            default:
                Color.clear.frame(height: 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private var recordButton: some View {
        Button(action: viewModel.toggleRecording) {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .frame(width: 84, height: 84)
                    .overlay(Circle().stroke(buttonStroke, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.25), radius: 7, y: 3)

                buttonIcon.foregroundStyle(buttonIconColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.state == .processing || viewModel.state == .waitingForSession)
        .opacity(viewModel.state == .processing || viewModel.state == .waitingForSession ? 0.7 : 1)
    }

    private var buttonFill: Color {
        switch viewModel.state {
        case .recording: return Theme.recording
        case .processing: return Theme.surface
        case .success: return Theme.success.opacity(0.9)
        default: return Theme.accent
        }
    }

    private var buttonStroke: Color {
        switch viewModel.state {
        case .recording: return Theme.recording.opacity(0.95)
        case .processing: return Theme.surfaceBorder
        case .success: return Theme.success.opacity(0.95)
        default: return Theme.accent.opacity(0.95)
        }
    }

    private var buttonIconColor: Color {
        viewModel.state == .processing ? Theme.textSecondary : .white
    }

    @ViewBuilder
    private var buttonIcon: some View {
        switch viewModel.state {
        case .processing:
            ProgressView().tint(Theme.textPrimary).scaleEffect(1.05)
        case .recording:
            RoundedRectangle(cornerRadius: 4).frame(width: 22, height: 22)
        case .success:
            Image(systemName: "checkmark").font(.system(size: 26, weight: .bold))
        default:
            Image(systemName: "mic.fill").font(.system(size: 30, weight: .semibold))
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 8) {
            if viewModel.state == .recording || viewModel.state == .processing {
                ControlButton(icon: "xmark", tint: Theme.recording, action: viewModel.cancelRecording)
            } else {
                ControlButton(icon: "trash", tint: Theme.textPrimary, action: viewModel.clearAll)
            }

            ControlButton(
                icon: "arrow.uturn.backward",
                tint: Theme.textPrimary,
                isDisabled: !viewModel.canUndo,
                action: viewModel.undoLastInsertion
            )

            ControlButton(icon: "delete.left", tint: Theme.textPrimary, action: viewModel.deleteBackward)

            ControlButton(icon: "return", tint: Theme.textPrimary, action: viewModel.insertReturn)
        }
    }
}

// MARK: - Reusable Components

private struct ControlButton: View {
    let icon: String
    let tint: Color
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.surfaceBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}

private struct PulseDot: View {
    let color: Color
    @State private var isOn = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isOn ? 1.1 : 0.85)
            .opacity(isOn ? 1 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    isOn = true
                }
            }
    }
}

private struct RecorderTicker: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<6, id: \.self) { i in
                    let wave = abs(sin(t * 3.1 + Double(i) * 0.55))
                    let height = 6 + (wave * 12)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 4, height: height)
                }
            }
            .frame(height: 20)
        }
    }
}

struct RepeatableButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label

    @State private var timer: Timer?

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    var body: some View {
        label()
            .frame(maxWidth: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if timer == nil {
                            action()
                            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in action() }
                        }
                    }
                    .onEnded { _ in
                        timer?.invalidate()
                        timer = nil
                    }
            )
    }
}
