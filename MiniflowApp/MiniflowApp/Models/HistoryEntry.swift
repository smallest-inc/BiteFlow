import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id: String
    let timestamp: String
    let transcript: String
    let entryType: String
    let actions: [HistoryAction]
    let success: Bool

    var formattedTimestamp: String {
        // ISO 8601 → readable
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: timestamp) {
            let fmt = DateFormatter()
            fmt.dateStyle = .short
            fmt.timeStyle = .short
            return fmt.string(from: date)
        }
        return timestamp
    }
}

struct HistoryAction: Codable {
    let action: String
    let success: Bool
    let message: String
}
