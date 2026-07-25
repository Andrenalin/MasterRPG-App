// @copyright André Trettin

import SwiftUI

struct ThemeGridSection: View {
    let title: LocalizedStringResource
    let themeIDs: [AppThemeID]

    @Environment(AppSettingsModel.self) private var settingsModel

    private let columns = [
        GridItem(.adaptive(minimum: 138), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(themeIDs) { themeID in
                    Button {
                        settingsModel.appThemeID = themeID
                    } label: {
                        ThemePreviewCard(
                            themeID: themeID,
                            showsName: true,
                            isSelected: settingsModel.appThemeID == themeID
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(themeID.localizedName))
                    .accessibilityValue(
                        settingsModel.appThemeID == themeID
                            ? Text("Selected", bundle: .module)
                            : Text("")
                    )
                    .accessibilityAddTraits(
                        settingsModel.appThemeID == themeID ? .isSelected : []
                    )
                }
            }
        }
    }
}

#Preview("Theme grid") {
    ScrollView {
        ThemeGridSection(
            title: "Themes",
            themeIDs: AppThemeID.allCases
        )
        .padding()
    }
    .environment(AppSettingsModel.previewFixture(appThemeID: .midnight))
}
