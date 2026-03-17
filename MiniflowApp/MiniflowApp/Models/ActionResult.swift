import Foundation

struct ActionResult: Codable, Identifiable {
    let action: String
    let success: Bool
    let message: String
    var id: String = UUID().uuidString

    enum CodingKeys: String, CodingKey {
        case action, success, message
    }
}
