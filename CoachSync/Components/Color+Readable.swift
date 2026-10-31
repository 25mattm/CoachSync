/// Colors that meet the 4.5:1 text contrast minimum, unlike the bright system colors they replace.
import SwiftUI

extension Color {
    /// Text, icons and chart marks in a status hue, on the app's backgrounds and light tints.
    static let readableGreen = adaptive(light: 0x176F30, dark: 0x30D158)
    static let readableOrange = adaptive(light: 0xA64B00, dark: 0xFF9F0A)
    static let readableRed = adaptive(light: 0xC41E16, dark: 0xFF6961)
    static let readableBlue = adaptive(light: 0x0A5FD6, dark: 0x64B0FF)
    static let readablePurple = adaptive(light: 0x7A3FC9, dark: 0xBF8CFF)
    static let readableCyan = adaptive(light: 0x0B6E8A, dark: 0x64D2FF)
    static let readablePink = adaptive(light: 0xB8235A, dark: 0xFF6482)
    static let readableYellow = adaptive(light: 0x8A6500, dark: 0xFFD60A)
    static let readableGray = adaptive(light: 0x5F5F66, dark: 0xAEAEB2)
    /// Secondary text on Liquid Glass and materials, which lower the system `.secondary` contrast.
    static let readableSecondary = adaptive(light: 0x4D4D52, dark: 0xC7C7CC)

    /// Fills behind white text. The same in both appearances, since the text is white in both.
    static let filledGreen = Color(hex: 0x176F30)
    static let filledOrange = Color(hex: 0xA64B00)
    static let filledRed = Color(hex: 0xC41E16)
    static let filledGray = Color(hex: 0x5F5F66)

    private init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
#if os(iOS)
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
#else
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
#endif
    }
}
