import SwiftUI

struct HomeTab: View {
    @ObservedObject var vm: AgentViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Welcome header + stats
                HStack(alignment: .firstTextBaseline) {
                    Text(vm.userName.isEmpty
                         ? "Welcome back"
                         : "Welcome back, \(vm.userName)")
                        .font(.custom("GeistPixel-Square", size: 28))
                        .foregroundStyle(Color.black)

                    Spacer()

                    statPill(value: vm.totalWordsTranscribed == 0 ? "0" : "\(vm.totalWordsTranscribed)",
                             label: "words")
                }

                // Fn hint card
                fnCard

                // History
                if !vm.history.isEmpty {
                    historySection
                }
            }
            .padding(28)
        }
    }

    // MARK: - Stat pill

    private func statPill(value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
        }
    }

    // MARK: - Fn Card

    private var fnCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if vm.isListening || vm.isProcessing {
                DictationWidget(vm: vm)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Title row: Hold [Fn] to start dictating
                    HStack(spacing: 0) {
                        Text("Hold ")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.black)
                        Text("Fn")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.fnBadgeBg)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text(" to start dictating")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.black)
                    }

                    Text("Speak Naturally  –  Miniflow transcribes and executes your voice commands in any app")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fnCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.fnCardBorder, lineWidth: 1)
        )
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(groupedHistory, id: \.key) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.key)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.black)
                        Spacer()
                        Button("Clear all") {
                            Task {
                                try? await APIClient.shared.invokeVoid("clear_history")
                                await vm.loadHistory()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textMuted)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { idx, entry in
                            HistoryRow(entry: entry)
                            if idx < group.entries.count - 1 {
                                Divider().padding(.leading, 90)
                            }
                        }
                    }
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "E5E5EA"), lineWidth: 1))
                }
            }
        }
    }

    private var groupedHistory: [(key: String, date: Date, entries: [HistoryEntry])] {
        var buckets: [String: (date: Date, entries: [HistoryEntry])] = [:]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d, yyyy"

        for entry in vm.history {
            guard let date = iso.date(from: entry.timestamp) else { continue }
            let key = fmt.string(from: date).uppercased()
            if buckets[key] == nil {
                buckets[key] = (date: date, entries: [])
            }
            buckets[key]!.entries.append(entry)
        }

        return buckets
            .map { (key: $0.key, date: $0.value.date, entries: $0.value.entries) }
            .sorted { $0.date > $1.date }
    }

}

// MARK: - History Row

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(formattedTime(entry.timestamp))
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
                .frame(width: 68, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.transcript)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black)
                    .lineLimit(2)

                if !entry.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(actionTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "2D6B5E"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "E4F3EC"))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var actionTags: [String] {
        var seen = Set<String>()
        return entry.actions.compactMap { action in
            let label = action.action.prefix(1).uppercased() + action.action.dropFirst()
            return seen.insert(label).inserted ? label : nil
        }
    }

    private func formattedTime(_ timestamp: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: timestamp) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "hh:mm a"
        return fmt.string(from: date)
    }
}
