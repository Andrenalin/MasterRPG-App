// @copyright André Trettin

import SwiftUI
import Testing
@testable import CoreRPG

@Suite("App themes")
struct AppThemeTests {
    @Test("Catalog contains every theme exactly once")
    func catalogCompleteness() {
        let catalogIDs = AppThemeCatalog.all.map(\.id)

        #expect(Set(catalogIDs).count == catalogIDs.count)
        #expect(Set(catalogIDs) == Set(AppThemeID.allCases))
    }

    @Test("Theme text and module colors meet contrast targets")
    func contrast() {
        for themeID in AppThemeID.allCases {
            for colorScheme in [ColorScheme.light, .dark] {
                for contrast in [ColorSchemeContrast.standard, .increased] {
                    let theme = AppThemeCatalog.resolve(
                        themeID,
                        colorScheme: colorScheme,
                        contrast: contrast
                    )
                    let moduleMinimum = contrast == .increased ? 7.0 : 4.5
                    let accentMinimum = contrast == .increased ? 4.5 : 3.0
                    let context = "\(themeID.rawValue) \(colorScheme) \(contrast)"

                    #expect(
                        theme.foreground.contrastRatio(with: theme.canvas) >= 4.5,
                        "Foreground on canvas: \(context)"
                    )
                    #expect(
                        theme.foreground.contrastRatio(with: theme.canvasEnd) >= 4.5,
                        "Foreground on canvas end: \(context)"
                    )
                    #expect(
                        theme.foreground.contrastRatio(with: theme.panel) >= 4.5,
                        "Foreground on panel: \(context)"
                    )
                    #expect(
                        theme.secondaryForeground.contrastRatio(with: theme.canvas) >= 4.5,
                        "Secondary foreground on canvas: \(context)"
                    )
                    #expect(
                        theme.secondaryForeground.contrastRatio(with: theme.panel) >= 4.5,
                        "Secondary foreground on panel: \(context)"
                    )
                    #expect(
                        theme.accent.contrastRatio(with: theme.canvas) >= accentMinimum,
                        "Accent on canvas: \(context)"
                    )

                    for module in NetworkModules.allCases {
                        let colors = theme.components(for: module)
                        #expect(
                            colors.tint.contrastRatio(with: colors.background) >= moduleMinimum,
                            "Insufficient \(context) \(module.token) contrast"
                        )
                    }
                }
            }
        }
    }
}
