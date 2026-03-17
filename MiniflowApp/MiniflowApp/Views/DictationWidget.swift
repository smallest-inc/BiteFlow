import SwiftUI

/// The fn card's inner content.
/// Idle: descriptive text on left + mic button on right.
/// Active: transcript text replaces the description.
struct DictationWidget: View {
    @ObservedObject var vm: AgentViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: text content
            VStack(alignment: .leading, spacing: 4) {
                if vm.isListening {
                    Text("Listening…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black)
                } else {
                    HStack(spacing: 6) {
                        Text("Hold")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.black)
                        Text("fn")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentBrown)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.fnCardBorder)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text("to start dictating")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.black)
                    }
                    Text("Speak naturally — MiniFlow transcribes and executes your voice commands in any app.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(err.contains("clipboard") ? .orange : .red)
                        .lineLimit(2)

                    if vm.needsAccessibility {
                        Button("Enable Accessibility") {
                            vm.openAccessibilitySettings()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentBrown)
                        .buttonStyle(.plain)
                        .underline()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: mic button
            Button {
                Task {
                    if vm.isListening { await vm.stopListening() }
                    else              { await vm.startListening() }
                }
            } label: {
                ZStack {
                    if vm.isListening {
                        Circle()
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 48, height: 48)
                            .scaleEffect(1.2)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: vm.isListening
                            )
                    }
                    Circle()
                        .fill(vm.isListening ? Color.red.opacity(0.15) : Color.fnCardBorder.opacity(0.6))
                        .frame(width: 38, height: 38)
                    Image(systemName: vm.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(vm.isListening ? .red : Color.accentBrown)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
