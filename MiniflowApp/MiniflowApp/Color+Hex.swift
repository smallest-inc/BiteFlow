import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Design Tokens

extension Color {
    static let bgWarm      = Color(hex: "F3F3F1")  // sidebar / window bg
    static let fnCardBg    = Color(hex: "FFFCF0")  // fn card fill
    static let fnCardBorder = Color(hex: "EDE6C3") // fn card border
    static let accentBrown = Color(hex: "7A5C1E")  // logo, send button
    static let navActive   = Color(hex: "E3E3E0")  // active nav item
    static let textMuted   = Color(hex: "6B6B70")  // secondary text
    static let successGreen = Color(hex: "2D6A4F")
    static let errorRed    = Color(hex: "9B1C1C")
}
