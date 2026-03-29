import Foundation
import Combine
import AppKit

@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var smallestKey = ""
    @Published var groqKey = ""
    @Published var userName = ""
    @Published var isLoading = false
    @Published var saveStatus: String?

    private let api = APIClient.shared
    init() {}

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if let keys: ApiKeysResponse = try? await api.invoke("has_api_keys") {
            smallestKey = keys.smallest ?? ""
            groqKey = keys.groq ?? ""
        }
        if let name: String = try? await api.invoke("get_user_name") {
            userName = name
        }
    }

    // MARK: - Save API Keys / Profile

    func saveSmallestKey() async -> Bool {
        do {
            try await api.invokeVoid("save_api_key", body: ["service": "smallest", "key": smallestKey])
            return true
        } catch {
            return false
        }
    }

    func saveGroqKey() async -> Bool {
        do {
            try await api.invokeVoid("save_api_key", body: ["service": "groq", "key": groqKey])
            return true
        } catch {
            return false
        }
    }

    func saveUserName() async {
        try? await api.invokeVoid("save_user_name", body: ["name": userName])
        flashStatus("Saved")
    }

    // MARK: - Helpers

    private func flashStatus(_ message: String) {
        saveStatus = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveStatus = nil
        }
    }

    private struct ApiKeysResponse: Decodable {
        let smallest: String?
        let groq: String?
    }
}
