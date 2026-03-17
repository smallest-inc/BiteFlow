import SwiftUI

// MARK: - Full Right Panel

struct ActionFeedPanel: View {
    @ObservedObject var vm: AgentViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                if vm.isProcessing {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                        .scaleEffect(vm.isProcessing ? 1.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                            value: vm.isProcessing
                        )
                }
                Text("Actions")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Clear") { vm.clearActions() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(vm.actions.enumerated()), id: \.element.id) { index, action in
                        ActionRow(action: action)
                        if index < vm.actions.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                                .opacity(0.15)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 280)
        .background(.white)
        .overlay(
            Rectangle()
                .fill(Color.navActive)
                .frame(width: 1),
            alignment: .leading
        )
    }
}

// MARK: - Inline Feed (for backwards compat)

struct ActionFeed: View {
    let actions: [ActionResult]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                ActionRow(action: action)
                if index < actions.count - 1 {
                    Divider()
                        .padding(.leading, 40)
                        .opacity(0.15)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Action Row

struct ActionRow: View {
    let action: ActionResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(action.success ? .green : .red)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(actionLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Text(action.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var actionLabel: String {
        action.action
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
