import SwiftUI

// MARK: - ViewModel

@MainActor
final class ShortcutsViewModel: ObservableObject {
    @Published var entries: [(trigger: String, expansion: String)] = []
    @Published var isLoading = false
    private let api = APIClient.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let dict: [String: String] = try? await api.invoke("get_shortcuts") {
            entries = dict.map { (trigger: $0.key, expansion: $0.value) }
                         .sorted { $0.trigger < $1.trigger }
        }
    }

    func add(trigger: String, expansion: String) async {
        try? await api.invokeVoid("add_shortcut", body: ["trigger": trigger, "expansion": expansion])
        await load()
    }

    func remove(trigger: String) async {
        try? await api.invokeVoid("remove_shortcut", body: ["trigger": trigger])
        entries.removeAll { $0.trigger == trigger }
    }
}

// MARK: - View

struct ShortcutsTab: View {
    @StateObject private var vm = ShortcutsViewModel()
    @State private var showAddSheet = false
    @State private var editingEntry: (trigger: String, expansion: String)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text("Shortcuts")
                        .font(.custom("GeistPixel-Square", size: 28))
                        .foregroundStyle(Color.black)
                    Spacer()
                    Button { showAddSheet = true } label: {
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
                    Text("Say it once. Use it forever")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black)
                    Text("Save your most-used text as shortcuts, links, intros, sign-offs, addresses and speak them into any app in seconds. No retyping, no hunting through old messages.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fnCardBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.fnCardBorder, lineWidth: 1))

                // Entries
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if !vm.entries.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.entries.enumerated()), id: \.element.trigger) { idx, entry in
                            ShortcutRow(
                                entry: entry,
                                onEdit: { editingEntry = entry },
                                onDelete: { Task { await vm.remove(trigger: entry.trigger) } }
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
            AddShortcutSheet { trigger, expansion in
                Task { await vm.add(trigger: trigger, expansion: expansion) }
            }
        }
        .sheet(item: Binding(
            get: { editingEntry.map { IdentifiableTrigger(trigger: $0.trigger, expansion: $0.expansion) } },
            set: { editingEntry = $0.map { (trigger: $0.trigger, expansion: $0.expansion) } }
        )) { entry in
            AddShortcutSheet(initialTrigger: entry.trigger, initialExpansion: entry.expansion) { trigger, expansion in
                Task {
                    await vm.remove(trigger: entry.trigger)
                    await vm.add(trigger: trigger, expansion: expansion)
                }
            }
        }
    }
}

// MARK: - Shortcut Row

private struct ShortcutRow: View {
    let entry: (trigger: String, expansion: String)
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.trigger)
                .font(.system(size: 13))
                .foregroundStyle(Color.black)
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(Color.textMuted)
            Text(entry.expansion)
                .font(.system(size: 13))
                .foregroundStyle(Color.black)
                .lineLimit(1)
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

private struct AddShortcutSheet: View {
    var initialTrigger: String = ""
    var initialExpansion: String = ""
    var onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var trigger: String
    @State private var expansion: String

    init(initialTrigger: String = "", initialExpansion: String = "", onSave: @escaping (String, String) -> Void) {
        self.initialTrigger = initialTrigger
        self.initialExpansion = initialExpansion
        self.onSave = onSave
        _trigger = State(initialValue: initialTrigger)
        _expansion = State(initialValue: initialExpansion)
    }

    private var expansionPlaceholder: AttributedString {
        var s = AttributedString("e.g. john@example.com")
        s.foregroundColor = Color(hex: "BBBBBB")
        s.link = nil
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Title row
            HStack {
                Text(initialTrigger.isEmpty ? "Add a new shortcut" : "Edit shortcut")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Fields
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shortcut")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                    TextField("e.g. my email address", text: $trigger)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Expansion")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                    ZStack(alignment: .topLeading) {
                        if expansion.isEmpty {
                            Text(expansionPlaceholder)
                                .font(.system(size: 13))
                                .padding(.leading, 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        PlainTextEditor(text: $expansion)
                            .frame(height: 80)
                    }
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: "D1D1D6"), lineWidth: 1)
                    )
                }
            }

            // Actions
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textMuted)
                    .padding(.trailing, 8)
                Button(initialTrigger.isEmpty ? "Add shortcut" : "Save") {
                    let t = trigger.trimmingCharacters(in: .whitespaces)
                    let e = expansion.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, !e.isEmpty else { return }
                    onSave(t, e)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    (trigger.trimmingCharacters(in: .whitespaces).isEmpty ||
                     expansion.trimmingCharacters(in: .whitespaces).isEmpty)
                    ? Color.gray : Color.fnBadgeBg
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty ||
                          expansion.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - Plain Text Editor (no link detection)

private struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.lineFragmentPadding = 5
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text { textView.string = text }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        init(_ parent: PlainTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - Helpers

private struct IdentifiableTrigger: Identifiable {
    let id: String
    let trigger: String
    let expansion: String
    init(trigger: String, expansion: String) {
        self.id = trigger
        self.trigger = trigger
        self.expansion = expansion
    }
}
