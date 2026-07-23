// @copyright André Trettin

import SwiftUI

struct ThemePreviewCard: View {
    let themeID: AppThemeID
    let showsName: Bool
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let theme = AppThemeCatalog.resolve(
            themeID,
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )

        VStack(alignment: .leading) {
            ThemeMiniature(theme: theme)
                .aspectRatio(1.55, contentMode: .fit)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.accentColor, lineWidth: 3)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, theme.accentColor)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }

            if showsName {
                Text(themeID.localizedName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview("Theme preview") {
    ThemePreviewCard(themeID: .neonRealm, showsName: true, isSelected: true)
        .frame(width: 180)
        .padding()
}
