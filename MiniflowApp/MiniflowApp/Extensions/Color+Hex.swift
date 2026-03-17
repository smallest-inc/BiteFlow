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
    static let bgWarm       = Color(hex: "FAFAFA")  // sidebar bg
    static let fnCardBg     = Color(hex: "EEF8F2")  // fn card fill (mint)
    static let fnCardBorder = Color(hex: "D4EDE0")  // fn card border
    static let fnBadgeBg    = Color(hex: "2D6B5E")  // Fn key badge
    static let accentBrown  = Color(hex: "7A5C1E")  // legacy accent
    static let navActive    = Color(hex: "EFEFEF")  // active nav item
    static let textMuted    = Color(hex: "888888")  // secondary text
    static let successGreen = Color(hex: "34C759")
    static let errorRed     = Color(hex: "FF3B30")
}
