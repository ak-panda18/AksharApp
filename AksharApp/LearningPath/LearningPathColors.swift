import SwiftUI

extension Color {
    static let aksharPrimaryGold = Color(hex: 0xC9A96E)
    static let aksharGoldDark = Color(hex: 0x8B6914)
    static let aksharGoldLight = Color(hex: 0xF5EDD8)
    static let aksharSurfaceDark = Color(hex: 0x1A1A1A)
    static let aksharCreamBG = Color(hex: 0xFDFAF5)
    static let aksharMuted = Color(hex: 0x888888)
    
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}
