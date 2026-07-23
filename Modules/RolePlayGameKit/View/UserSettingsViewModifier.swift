// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct UserSettingsViewModifier: ViewModifier {
    public init(appModel: AppModel) {
        self.settingsModel = appModel.settingsModel
    }
    
    let settingsModel: AppSettingsModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func body(content: Content) -> some View {
        let theme = AppThemeCatalog.resolve(
            settingsModel.appThemeID,
            colorScheme: effectiveColorScheme,
            contrast: colorSchemeContrast
        )

        content
            .tint(theme.accentColor)
            .background {
                if reduceTransparency {
                    theme.canvas.color
                        .ignoresSafeArea()
                } else {
                    theme.backgroundGradient
                        .ignoresSafeArea()
                }
            }
            .environment(\.appTheme, theme)
#if os(iOS)
            .applyIf(settingsModel.appColorScheme != .system) {
                $0.environment(\.colorScheme, effectiveColorScheme)
            }
#endif
    }

    private var effectiveColorScheme: ColorScheme {
#if os(iOS)
        settingsModel.appColorScheme.colorScheme(for: colorScheme)
#else
        colorScheme
#endif
    }
}
