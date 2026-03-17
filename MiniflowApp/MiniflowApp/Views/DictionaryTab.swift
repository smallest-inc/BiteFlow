import SwiftUI

// MARK: - ViewModel

@MainActor
final class DictionaryViewModel: ObservableObject {
    @Published var entries: [(from: String, to: String)] = []
    @Published var isLoading = false
    private let api = APIClient.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let dict: [String: String] = try? await api.invoke("get_dictionary") {
            entries = dict.map { (from: $0.key, to: $0.value) }
                         .sorted { $0.from < $1.from }
        }
    }

    func add(from: String, to: String) async {
        try? await api.invokeVoid("add_dictionary_word", body: ["from": from, "to": to])
        await load()
    }

    func remove(from: String) async {
        try? await api.invokeVoid("remove_dictionary_word", body: ["from": from])
        entries.removeAll { $0.from == from }
    }
}

// MARK: - View

struct DictionaryTab: View {
    @StateObject private var vm = DictionaryViewModel()
    @State private var showAddSheet = false
    @State private var editingEntry: (from: String, to: String)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text("Dictionary")
                        .font(.custom("GeistPixel-Square", size: 28))
                        .foregroundStyle(Color.black)
                    Spacer()
                    Button {
                        showAddSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Add New")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.fnBadgeBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                // Info card
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your words, always spelled right")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black)
                    Text("MiniFlow learns your unique words and names as you speak, or add them yourself. From client names to industry jargon, make sure MiniFlow always gets it right.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fnCardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.fnCardBorder, lineWidth: 1))

                // Entries list
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if !vm.entries.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.entries.enumerated()), id: \.element.from) { idx, entry in
                            DictionaryRow(
                                entry: entry,
                                onEdit: { editingEntry = entry },
                                onDelete: { Task { await vm.remove(from: entry.from) } }
                            )
                            if idx < vm.entries.count - 1 {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "E5E5EA"), lineWidth: 1))
                }
            }
            .padding(28)
        }
        .task { await vm.load() }
        .sheet(isPresented: $showAddSheet) {
            AddDictionaryEntrySheet { from, to in
                Task { await vm.add(from: from, to: to) }
            }
        }
        .sheet(item: Binding(
            get: { editingEntry.map { IdentifiableEntry(from: $0.from, to: $0.to) } },
            set: { editingEntry = $0.map { (from: $0.from, to: $0.to) } }
        )) { entry in
            AddDictionaryEntrySheet(initialFrom: entry.from, initialTo: entry.to) { from, to in
                Task {
                    await vm.remove(from: entry.from)
                    await vm.add(from: from, to: to)
                }
            }
        }
    }
}

// MARK: - Dictionary Row

private struct DictionaryRow: View {
    let entry: (from: String, to: String)
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.from)
                .font(.system(size: 13))
                .foregroundStyle(Color.black)
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
            Text(entry.to)
                .font(.system(size: 13))
                .foregroundStyle(Color.black)
            Spacer()
            if isHovered {
                HStack(spacing: 12) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Add / Edit Sheet

private struct AddDictionaryEntrySheet: View {
    var initialFrom: String = ""
    var initialTo: String = ""
    var onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fromWord: String
    @State private var toWord: String

    init(initialFrom: String = "", initialTo: String = "", onSave: @escaping (String, String) -> Void) {
        self.initialFrom = initialFrom
        self.initialTo = initialTo
        self.onSave = onSave
        _fromWord = State(initialValue: initialFrom)
        _toWord = State(initialValue: initialTo)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(initialFrom.isEmpty ? "Add Word" : "Edit Word")
                .font(.custom("GeistPixel-Square", size: 20))
                .foregroundStyle(Color.black)

            VStack(alignment: .leading, spacing: 8) {
                Text("Say this…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                TextField("e.g. on my way", text: $fromWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Replace with…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                TextField("e.g. omw", text: $toWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
                    .padding(.trailing, 8)
                Button("Save") {
                    let f = fromWord.trimmingCharacters(in: .whitespaces)
                    let t = toWord.trimmingCharacters(in: .whitespaces)
                    guard !f.isEmpty, !t.isEmpty else { return }
                    onSave(f, t)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.fnBadgeBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(fromWord.trimmingCharacters(in: .whitespaces).isEmpty
                          || toWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}

// MARK: - Helpers

private struct IdentifiableEntry: Identifiable {
    let id: String
    let from: String
    let to: String
    init(from: String, to: String) {
        self.id = from
        self.from = from
        self.to = to
    }
}
