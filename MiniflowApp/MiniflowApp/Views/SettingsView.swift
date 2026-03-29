import SwiftUI
import ServiceManagement

struct SettingsTab: View {
    @StateObject private var vm = SettingsViewModel()
    @State private var selectedSection = "keys"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                Text("Settings")
                    .font(.custom("GeistPixel-Square", size: 28))
                    .foregroundStyle(Color.black)

                // Sub-tab row
                HStack(spacing: 4) {
                    subTab(id: "keys",    label: "API Keys")
                    subTab(id: "profile", label: "Profile")
                    subTab(id: "general", label: "General")
                }
                .padding(4)
                .background(Color(hex: "F2F2F2"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, alignment: .leading)

                // Content
                Group {
                    switch selectedSection {
                    case "profile": profileSection
                    case "general": generalSection
                    default:        apiKeysSection
                    }
                }
            }
            .padding(28)
        }
        .task { await vm.load() }
    }

    // MARK: - Sub-tab button

    private func subTab(id: String, label: String) -> some View {
        Button { selectedSection = id } label: {
            Text(label)
                .font(.system(size: 12, weight: selectedSection == id ? .semibold : .regular))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selectedSection == id ? Color.white : Color.clear)
                        .shadow(color: selectedSection == id ? .black.opacity(0.06) : .clear,
                                radius: 2, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - API Keys

    @State private var smallestSaveState: SaveState = .idle
    @State private var groqSaveState: SaveState = .idle
    enum SaveState { case idle, saving, saved, error }

    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Smallest AI")
                    HStack(spacing: 10) {
                        SecureField("API Key", text: $vm.smallestKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .onChange(of: vm.smallestKey) { _ in smallestSaveState = .idle }
                        saveButton(state: smallestSaveState, disabled: vm.smallestKey.isEmpty) {
                            smallestSaveState = .saving
                            let ok = await vm.saveSmallestKey()
                            smallestSaveState = ok ? .saved : .error
                        }
                    }
                    stateHint(state: smallestSaveState, hint: "Used for real-time speech-to-text.")
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Groq")
                    HStack(spacing: 10) {
                        SecureField("API Key", text: $vm.groqKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .onChange(of: vm.groqKey) { _ in groqSaveState = .idle }
                        saveButton(state: groqSaveState, disabled: vm.groqKey.isEmpty) {
                            groqSaveState = .saving
                            let ok = await vm.saveGroqKey()
                            groqSaveState = ok ? .saved : .error
                        }
                    }
                    stateHint(state: groqSaveState, hint: "Used for AI transcript formatting (Qwen3-32B).")
                }
            }
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Display Name")
                    HStack(spacing: 10) {
                        TextField("Your name", text: $vm.userName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                        Button("Save") {
                            Task { await vm.saveUserName() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(vm.userName.isEmpty ? Color.gray : Color.fnBadgeBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(vm.userName.isEmpty)
                    }
                    if let status = vm.saveStatus {
                        Text(status)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.fnBadgeBg)
                    }
                }
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    if #available(macOS 13, *) {
                        settingsRow(
                            title: "Launch at Login",
                            subtitle: "MiniFlow will start automatically when you log in."
                        ) {
                            Toggle("", isOn: Binding<Bool>(
                                get: { SMAppService.mainApp.status == .enabled },
                                set: { enabled in
                                    if enabled { try? SMAppService.mainApp.register() }
                                    else       { try? SMAppService.mainApp.unregister() }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        Divider().padding(.horizontal, 16)
                    }

                    settingsRow(
                        title: "Accessibility Permission",
                        subtitle: "Required for MiniFlow to type into other apps."
                    ) {
                        Button("Open") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            )
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.fnBadgeBg)
                    }

                    Divider().padding(.horizontal, 16)

                    settingsRow(
                        title: "Fn Key Behaviour",
                        subtitle: "Set 'Press Fn key to' → 'Do Nothing' in Keyboard settings."
                    ) {
                        Button("Open") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.keyboard")!
                            )
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.fnBadgeBg)
                    }
                }
            }
        }
    }

    // MARK: - Shared components

    private func infoCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.black)
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fnCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.fnCardBorder, lineWidth: 1))
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "E5E5EA"), lineWidth: 1))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textMuted)
            .textCase(.uppercase)
    }

    private func settingsRow<Control: View>(title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func saveButton(state: SaveState, disabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Group {
                switch state {
                case .saving: ProgressView().controlSize(.small)
                case .saved:  Label("Saved", systemImage: "checkmark")
                case .error:  Label("Error", systemImage: "xmark.circle").foregroundStyle(Color.errorRed)
                case .idle:   Text("Save")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(disabled ? Color.gray : Color.fnBadgeBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(disabled || state == .saving)
    }

    private func stateHint(state: SaveState, hint: String) -> some View {
        Group {
            switch state {
            case .error:
                Text("Could not save — is the MiniFlow engine running?")
                    .foregroundStyle(Color.errorRed)
            default:
                Text(hint).foregroundStyle(Color.textMuted)
            }
        }
        .font(.system(size: 11))
    }
}
