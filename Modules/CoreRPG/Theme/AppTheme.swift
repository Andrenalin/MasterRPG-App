// @copyright André Trettin

import SwiftUI

public enum AppThemeID: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case standard
    case arcane
    case ember
    case midnight
    case sunrise
    case verdant
    case neonRealm

    public var id: String {
        rawValue
    }

    public var localizedName: LocalizedStringResource {
        switch self {
        case .standard:
            LocalizedStringResource("Standard", bundle: .module)
        case .arcane:
            LocalizedStringResource("Arcane", bundle: .module)
        case .ember:
            LocalizedStringResource("Ember", bundle: .module)
        case .midnight:
            LocalizedStringResource("Midnight", bundle: .module)
        case .sunrise:
            LocalizedStringResource("Sunrise", bundle: .module)
        case .verdant:
            LocalizedStringResource("Verdant", bundle: .module)
        case .neonRealm:
            LocalizedStringResource("Neon Realm", bundle: .module)
        }
    }

    public var icon: String {
        switch self {
        case .standard: "circle.grid.2x2"
        case .arcane: "wand.and.stars"
        case .ember: "flame"
        case .midnight: "moon.stars"
        case .sunrise: "sunrise"
        case .verdant: "leaf"
        case .neonRealm: "sparkles"
        }
    }
}

public struct ModuleThemeColors: Hashable, Sendable {
    public let tint: ThemeColorComponents
    public let background: ThemeColorComponents
}

public struct ResolvedAppTheme: Hashable, Sendable {
    public let id: AppThemeID
    public let canvas: ThemeColorComponents
    public let canvasEnd: ThemeColorComponents
    public let panel: ThemeColorComponents
    public let foreground: ThemeColorComponents
    public let secondaryForeground: ThemeColorComponents
    public let accent: ThemeColorComponents
    public let moduleColors: [NetworkModules: ModuleThemeColors]

    public var accentColor: Color {
        accent.color
    }

    public var foregroundColor: Color {
        foreground.color
    }

    public var secondaryForegroundColor: Color {
        secondaryForeground.color
    }

    public var panelColor: Color {
        panel.color
    }

    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [canvas.color, canvasEnd.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public func tint(for module: NetworkModules) -> Color {
        components(for: module).tint.color
    }

    public func background(for module: NetworkModules) -> Color {
        components(for: module).background.color
    }

    public func components(for module: NetworkModules) -> ModuleThemeColors {
        moduleColors[module] ?? ModuleThemeColors(tint: accent, background: panel)
    }
}

public struct AppThemeDefinition: Hashable, Sendable {
    public let id: AppThemeID
    public let canvas: AdaptiveThemeColor
    public let canvasEnd: AdaptiveThemeColor
    public let panel: AdaptiveThemeColor
    public let foreground: AdaptiveThemeColor
    public let secondaryForeground: AdaptiveThemeColor
    public let accent: AdaptiveThemeColor
    public let moduleTints: [AdaptiveThemeColor]
    public let moduleBackgrounds: [AdaptiveThemeColor]?

    public init(
        id: AppThemeID,
        canvas: AdaptiveThemeColor,
        canvasEnd: AdaptiveThemeColor,
        panel: AdaptiveThemeColor,
        foreground: AdaptiveThemeColor,
        secondaryForeground: AdaptiveThemeColor,
        accent: AdaptiveThemeColor,
        moduleTints: [AdaptiveThemeColor],
        moduleBackgrounds: [AdaptiveThemeColor]? = nil
    ) {
        self.id = id
        self.canvas = canvas
        self.canvasEnd = canvasEnd
        self.panel = panel
        self.foreground = foreground
        self.secondaryForeground = secondaryForeground
        self.accent = accent
        self.moduleTints = moduleTints
        self.moduleBackgrounds = moduleBackgrounds
    }

    public func resolve(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> ResolvedAppTheme {
        let resolvedCanvas = canvas.components(colorScheme: colorScheme, contrast: contrast)
        let resolvedPanel = panel.components(colorScheme: colorScheme, contrast: contrast)
        let minimumAccentContrast = contrast == .increased ? 4.5 : 3
        let minimumModuleContrast = contrast == .increased ? 7 : 4.5
        let resolvedAccent = accent
            .components(colorScheme: colorScheme, contrast: contrast)
            .ensuringContrast(
                against: resolvedCanvas,
                minimumRatio: minimumAccentContrast
            )

        var resolvedModuleColors: [NetworkModules: ModuleThemeColors] = [:]
        for module in NetworkModules.allCases {
            guard let index = module.themePaletteIndex, moduleTints.indices.contains(index) else {
                resolvedModuleColors[module] = ModuleThemeColors(
                    tint: resolvedAccent.ensuringContrast(
                        against: resolvedPanel,
                        minimumRatio: minimumModuleContrast
                    ),
                    background: resolvedPanel
                )
                continue
            }

            let tint = moduleTints[index].components(colorScheme: colorScheme, contrast: contrast)
            let background: ThemeColorComponents
            if let moduleBackgrounds, moduleBackgrounds.indices.contains(index) {
                background = moduleBackgrounds[index].components(
                    colorScheme: colorScheme,
                    contrast: contrast
                )
            } else {
                let tintAmount = colorScheme == .dark ? 0.12 : 0.06
                background = resolvedCanvas.blended(with: tint, amount: tintAmount)
            }
            resolvedModuleColors[module] = ModuleThemeColors(
                tint: tint.ensuringContrast(
                    against: background,
                    minimumRatio: minimumModuleContrast
                ),
                background: background
            )
        }

        return ResolvedAppTheme(
            id: id,
            canvas: resolvedCanvas,
            canvasEnd: canvasEnd.components(colorScheme: colorScheme, contrast: contrast),
            panel: resolvedPanel,
            foreground: foreground.components(colorScheme: colorScheme, contrast: contrast),
            secondaryForeground: secondaryForeground.components(
                colorScheme: colorScheme,
                contrast: contrast
            ),
            accent: resolvedAccent,
            moduleColors: resolvedModuleColors
        )
    }
}

private extension NetworkModules {
    var themePaletteIndex: Int? {
        switch self {
        case .adventure: 0
        case .audio: 1
        case .value: 2
        case .dice: 3
        case .map: 4
        case .pdf: 5
        case .photo: 6
        case .space: 7
        case .table: 8
        case .weather: 9
        case .none, .game, .setting, .editor, .search, .generator, .rule:
            nil
        }
    }
}
