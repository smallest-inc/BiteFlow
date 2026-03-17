import SwiftUI

struct HistoryView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var isLoading = false
    @State private var searchText = ""

    private var filtered: [HistoryEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.transcript.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.regularMaterial)

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                emptyState
            } else {
                List(filtered) { entry in
                    HistoryRow(entry: entry)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 520, height: 440)
        .task { await loadHistory() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear All") { Task { await clearHistory() } }
                    .foregroundStyle(.red)
                    .disabled(entries.isEmpty)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No History" : "No Results")
                .font(.headline)
            Text(searchText.isEmpty
                 ? "Your voice commands will appear here."
                 : "Try a different search term.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        if let result: [HistoryEntry] = try? await APIClient.shared.invoke("get_history") {
            entries = result
        }
    }

    private func clearHistory() async {
        try? await APIClient.shared.invokeVoid("clear_history")
        entries = []
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(entry.success ? .green : .red)
                    .font(.system(size: 12))

                Text(entry.transcript)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Text(entry.formattedTimestamp)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if !entry.actions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(entry.actions.prefix(3), id: \.action) { action in
                        Text(action.action.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(action.success
                                          ? Color.green.opacity(0.12)
                                          : Color.red.opacity(0.12))
                            )
                            .foregroundStyle(action.success ? .green : .red)
                    }
                    if entry.actions.count > 3 {
                        Text("+\(entry.actions.count - 3)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
