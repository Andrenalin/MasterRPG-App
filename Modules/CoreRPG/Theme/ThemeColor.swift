// @copyright André Trettin

import SwiftUI

public struct ThemeColorComponents: Codable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public var relativeLuminance: Double {
        0.2126 * Self.linearized(red)
            + 0.7152 * Self.linearized(green)
            + 0.0722 * Self.linearized(blue)
    }

    public func contrastRatio(with other: ThemeColorComponents) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func ensuringContrast(
        against background: ThemeColorComponents,
        minimumRatio: Double
    ) -> ThemeColorComponents {
        guard contrastRatio(with: background) < minimumRatio else {
            return self
        }

        let blackContrast = Self.black.contrastRatio(with: background)
        let whiteContrast = Self.white.contrastRatio(with: background)
        let target = blackContrast > whiteContrast ? Self.black : Self.white

        var lowerBound = 0.0
        var upperBound = 1.0
        // Binary search the blend amount toward the target contrast ratio; 24
        // bisections converge to ~1/2^24 precision, far finer than any visible
        // color difference, well before floating-point bounds would collapse.
        for _ in 0..<24 {
            let amount = (lowerBound + upperBound) / 2
            let candidate = blended(with: target, amount: amount)
            if candidate.contrastRatio(with: background) >= minimumRatio {
                upperBound = amount
            } else {
                lowerBound = amount
            }
        }

        return blended(with: target, amount: upperBound)
    }

    func blended(with other: ThemeColorComponents, amount: Double) -> ThemeColorComponents {
        let clampedAmount = min(max(amount, 0), 1)
        let retainedAmount = 1 - clampedAmount
        return ThemeColorComponents(
            red: red * retainedAmount + other.red * clampedAmount,
            green: green * retainedAmount + other.green * clampedAmount,
            blue: blue * retainedAmount + other.blue * clampedAmount,
            alpha: alpha * retainedAmount + other.alpha * clampedAmount
        )
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

public struct AdaptiveThemeColor: Codable, Hashable, Sendable {
    public let light: ThemeColorComponents
    public let dark: ThemeColorComponents
    public let increasedLight: ThemeColorComponents
    public let increasedDark: ThemeColorComponents

    public init(
        light: ThemeColorComponents,
        dark: ThemeColorComponents,
        increasedLight: ThemeColorComponents? = nil,
        increasedDark: ThemeColorComponents? = nil
    ) {
        self.light = light
        self.dark = dark
        self.increasedLight = increasedLight ?? light.blended(with: .black, amount: 0.16)
        self.increasedDark = increasedDark ?? dark.blended(with: .white, amount: 0.18)
    }

    public func components(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> ThemeColorComponents {
        switch (colorScheme, contrast) {
        case (.light, .standard):
            light
        case (.light, .increased):
            increasedLight
        case (.dark, .standard):
            dark
        case (.dark, .increased):
            increasedDark
        @unknown default:
            colorScheme == .dark ? dark : light
        }
    }
}

public extension ThemeColorComponents {
    static let black = ThemeColorComponents(hex: 0x000000)
    static let white = ThemeColorComponents(hex: 0xFFFFFF)
}
