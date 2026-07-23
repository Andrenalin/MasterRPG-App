// @copyright André Trettin

import SwiftUI

public enum AppThemeCatalog {
    public static let all: [AppThemeDefinition] = [
        standard,
        arcane,
        ember,
        midnight,
        sunrise,
        verdant,
        neonRealm
    ]

    public static func definition(for id: AppThemeID) -> AppThemeDefinition {
        all.first { $0.id == id } ?? standard
    }

    public static func resolve(
        _ id: AppThemeID,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> ResolvedAppTheme {
        definition(for: id).resolve(colorScheme: colorScheme, contrast: contrast)
    }

    public static let standard = theme(
        id: .standard,
        canvas: surface(0xF7F8FA, 0x101114),
        canvasEnd: surface(0xEEF2FF, 0x0F172A),
        panel: surface(0xFFFFFF, 0x1C1C1E),
        accent: adaptive(0x1D4ED8, 0x3B82F6),
        lightTints: [
            0x4338CA, 0x7E22CE, 0x1D4ED8, 0xBE185D, 0x6D28D9,
            0xB91C1C, 0x92400E, 0x9A3412, 0x166534, 0xB54708
        ],
        darkTints: [
            0x7C83FF, 0xD946EF, 0x3B82F6, 0xEC4899, 0x956DF7,
            0xEF4444, 0xD97706, 0xEA580C, 0x16A34A, 0xE56B13
        ],
        lightBackgrounds: [
            0xEEF2FF, 0xFAF5FF, 0xEFF6FF, 0xFDF2F8, 0xF5F3FF,
            0xFEF2F2, 0xFFFBEB, 0xFFF7ED, 0xF0FDF4, 0xFFF7ED
        ],
        darkBackgrounds: [
            0x0F0E24, 0x260B35, 0x09162F, 0x35071B, 0x1D0B3A,
            0x320A0A, 0x2C1203, 0x2B0D03, 0x052012, 0x2B1003
        ]
    )

    public static let arcane = theme(
        id: .arcane,
        canvas: surface(0xF7F3FF, 0x120D26),
        canvasEnd: surface(0xEAF8FF, 0x071B2C),
        panel: surface(0xFCFAFF, 0x1D1636),
        accent: adaptive(0x6D28D9, 0x956DF7),
        lightTints: [
            0x4338CA, 0x7E22CE, 0x0E7490, 0xBE185D, 0x6D28D9,
            0x1D4ED8, 0xA21CAF, 0x0F766E, 0x4D7C0F, 0xB45309
        ],
        darkTints: [
            0x6366F1, 0xC026D3, 0x0891B2, 0xDB2777, 0x956DF7,
            0x3B82F6, 0xD946EF, 0x0D9488, 0x65A30D, 0xD97706
        ]
    )

    public static let ember = theme(
        id: .ember,
        canvas: surface(0xFFF6EE, 0x250C07),
        canvasEnd: surface(0xFFE9D5, 0x341207),
        panel: surface(0xFFFCF8, 0x32130D),
        accent: adaptive(0xC2410C, 0xEA580C),
        lightTints: [
            0xB91C1C, 0xC2410C, 0xA16207, 0x9F1239, 0x9A3412,
            0x991B1B, 0x854D0E, 0x7C2D12, 0xA21CAF, 0xB45309
        ],
        darkTints: [
            0xEF4444, 0xEA580C, 0xB45309, 0xE11D48, 0xD75C08,
            0xDC2626, 0xB45309, 0xEA580C, 0xC026D3, 0xD97706
        ]
    )

    public static let midnight = theme(
        id: .midnight,
        canvas: surface(0xEFF8FF, 0x061522),
        canvasEnd: surface(0xE3F5F7, 0x042B35),
        panel: surface(0xF8FCFF, 0x0D2430),
        accent: adaptive(0x0369A1, 0x0891B2),
        lightTints: [
            0x1D4ED8, 0x0E7490, 0x0F766E, 0x4338CA, 0x0369A1,
            0x1E40AF, 0x115E59, 0x6D28D9, 0x166534, 0x155E75
        ],
        darkTints: [
            0x3B82F6, 0x0891B2, 0x0D9488, 0x6366F1, 0x0284C7,
            0x3B82F6, 0x0D9488, 0x956DF7, 0x16A34A, 0x0891B2
        ]
    )

    public static let sunrise = theme(
        id: .sunrise,
        canvas: surface(0xFFF8E7, 0x251207),
        canvasEnd: surface(0xFFE7F2, 0x321029),
        panel: surface(0xFFFCF7, 0x321710),
        accent: adaptive(0x9F1239, 0xE11D48),
        lightTints: [
            0x92400E, 0xC2410C, 0xBE185D, 0x6D28D9, 0x9F1239,
            0xB91C1C, 0xA16207, 0x9A3412, 0x7E22CE, 0xB45309
        ],
        darkTints: [
            0xD97706, 0xEA580C, 0xDB2777, 0x956DF7, 0xE11D48,
            0xEF4444, 0xB45309, 0xEA580C, 0xC026D3, 0xE56B13
        ]
    )

    public static let verdant = theme(
        id: .verdant,
        canvas: surface(0xF1FBF4, 0x071C11),
        canvasEnd: surface(0xE7F9F2, 0x052923),
        panel: surface(0xFAFFFB, 0x0D2A1C),
        accent: adaptive(0x166534, 0x16A34A),
        lightTints: [
            0x166534, 0x0F766E, 0x3F6212, 0x1D4ED8, 0x047857,
            0x4D7C0F, 0xA16207, 0x115E59, 0x15803D, 0x0E7490
        ],
        darkTints: [
            0x16A34A, 0x0D9488, 0x65A30D, 0x3B82F6, 0x059669,
            0x65A30D, 0xB45309, 0x0D9488, 0x16A34A, 0x0891B2
        ]
    )

    public static let neonRealm = theme(
        id: .neonRealm,
        canvas: surface(0xF4F2FF, 0x090D2A),
        canvasEnd: surface(0xE6FBFF, 0x002E3E),
        panel: surface(0xFBFAFF, 0x15183A),
        accent: adaptive(0x6D28D9, 0x956DF7),
        lightTints: [
            0x6D28D9, 0xBE185D, 0x0E7490, 0x4D7C0F, 0x7E22CE,
            0x1D4ED8, 0x9F1239, 0x0F766E, 0x3F6212, 0xA21CAF
        ],
        darkTints: [
            0x956DF7, 0xEC4899, 0x0891B2, 0x65A30D, 0xD946EF,
            0x3B82F6, 0xE11D48, 0x0D9488, 0x16A34A, 0xC026D3
        ]
    )

    private static func theme(
        id: AppThemeID,
        canvas: AdaptiveThemeColor,
        canvasEnd: AdaptiveThemeColor,
        panel: AdaptiveThemeColor,
        accent: AdaptiveThemeColor,
        lightTints: [UInt32],
        darkTints: [UInt32],
        lightBackgrounds: [UInt32]? = nil,
        darkBackgrounds: [UInt32]? = nil
    ) -> AppThemeDefinition {
        let foreground = AdaptiveThemeColor(
            light: ThemeColorComponents(hex: 0x111827),
            dark: ThemeColorComponents(hex: 0xF9FAFB),
            increasedLight: .black,
            increasedDark: .white
        )
        let secondaryForeground = AdaptiveThemeColor(
            light: ThemeColorComponents(hex: 0x4B5563),
            dark: ThemeColorComponents(hex: 0xD1D5DB),
            increasedLight: ThemeColorComponents(hex: 0x374151),
            increasedDark: ThemeColorComponents(hex: 0xE5E7EB)
        )
        let tints = zip(lightTints, darkTints).map { adaptive($0, $1) }
        let backgrounds: [AdaptiveThemeColor]? = if let lightBackgrounds, let darkBackgrounds {
            zip(lightBackgrounds, darkBackgrounds).map { surface($0, $1) }
        } else {
            nil
        }

        return AppThemeDefinition(
            id: id,
            canvas: canvas,
            canvasEnd: canvasEnd,
            panel: panel,
            foreground: foreground,
            secondaryForeground: secondaryForeground,
            accent: accent,
            moduleTints: tints,
            moduleBackgrounds: backgrounds
        )
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> AdaptiveThemeColor {
        AdaptiveThemeColor(
            light: ThemeColorComponents(hex: light),
            dark: ThemeColorComponents(hex: dark)
        )
    }

    private static func surface(_ light: UInt32, _ dark: UInt32) -> AdaptiveThemeColor {
        let lightColor = ThemeColorComponents(hex: light)
        let darkColor = ThemeColorComponents(hex: dark)
        return AdaptiveThemeColor(
            light: lightColor,
            dark: darkColor,
            increasedLight: lightColor.blended(with: .white, amount: 0.5),
            increasedDark: darkColor.blended(with: .black, amount: 0.5)
        )
    }
}
