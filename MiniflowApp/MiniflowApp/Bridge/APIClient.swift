import Foundation

/// HTTP client for the MiniFlow Python backend (http://127.0.0.1:8765).
/// All invoke calls are POST /invoke/:command with a JSON body.
@MainActor
final class APIClient {

    static let shared = APIClient()

    private let base = URL(string: "http://127.0.0.1:8765")!

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: - Core invoke

    func invoke<T: Decodable>(_ command: String, body: [String: Any] = [:]) async throws -> T {
        let url = base.appendingPathComponent("invoke/\(command)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MiniflowError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try decoder.decode(T.self, from: data)
    }

    /// Convenience for commands that return nothing meaningful.
    /// Does NOT decode the response body — the Python backend returns JSON `null` for void commands,
    /// which JSONDecoder cannot decode into a struct and would throw typeMismatch.
    func invokeVoid(_ command: String, body: [String: Any] = [:]) async throws {
        let url = base.appendingPathComponent("invoke/\(command)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MiniflowError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    // MARK: - Health check

    func isBackendAlive() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8765/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Types

    private struct EmptyResponse: Decodable {}

    enum MiniflowError: LocalizedError {
        case httpError(Int)
        case backendNotRunning

        var errorDescription: String? {
            switch self {
            case .httpError(let code): return "Backend returned HTTP \(code)"
            case .backendNotRunning:   return "MiniFlow engine failed to start. Try relaunching the app."
            }
        }
    }
}
