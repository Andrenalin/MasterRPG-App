// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct UserSettingsViewModifier: ViewModifier {
    public init(appModel: AppModel, appliesBackground: Bool = true) {
        self.settingsModel = appModel.settingsModel
        self.appliesBackground = appliesBackground
    }

    let settingsModel: AppSettingsModel
    /// False for visionOS ImmersiveSpace content: an opaque themed background
    /// filling an `.ignoresSafeArea()` frame renders as a solid floating panel
    /// in the space instead of leaving passthrough/mixed reality visible.
    let appliesBackground: Bool

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
            .applyIf(appliesBackground) {
                $0.background {
                    if reduceTransparency {
                        theme.canvas.color
                            .ignoresSafeArea()
                    } else {
                        theme.backgroundGradient
                            .ignoresSafeArea()
                    }
                }
            }
            .environment(\.appTheme, theme)
#if os(iOS) || os(macOS)
            .applyIf(settingsModel.appColorScheme != .system) {
                $0.preferredColorScheme(effectiveColorScheme)
            }
#endif
    }

    private var effectiveColorScheme: ColorScheme {
#if os(iOS) || os(macOS)
        settingsModel.appColorScheme.colorScheme(for: colorScheme)
#else
        colorScheme
#endif
    }
}
