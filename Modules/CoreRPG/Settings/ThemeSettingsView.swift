// @copyright André Trettin

import SwiftUI

public struct ThemeSettingsView: View {
    public init() {}

    @Environment(AppSettingsModel.self) private var settingsModel
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPickerPresented = false

    public var body: some View {
        SectionGroupEditorView {
            Button(action: presentPicker) {
                HStack {
                    ThemePreviewCard(
                        themeID: settingsModel.appThemeID,
                        showsName: false,
                        isSelected: false
                    )
                    .frame(width: 104)

                    VStack(alignment: .leading) {
                        Text(settingsModel.appThemeID.localizedName)
                            .foregroundStyle(.primary)
                        Text("Choose a color theme", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Choose…", bundle: .module)
                        .foregroundStyle(theme.accentColor)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Theme", bundle: .module))
            .accessibilityValue(Text(settingsModel.appThemeID.localizedName))
        } header: {
            Text("Theme", bundle: .module)
        } footer: {
            Text("Themes change app surfaces and module colors without changing your photos, maps, or documents.", bundle: .module)
        }
        .sheet(isPresented: $isPickerPresented) {
            ThemePickerView()
                .environment(settingsModel)
                .environment(\.appTheme, theme)
                .environment(\.colorScheme, colorScheme)
        }
    }

    private func presentPicker() {
        isPickerPresented = true
    }
}

#Preview {
    List {
        ThemeSettingsView()
    }
    .environment(AppSettingsModel.previewFixture(appThemeID: .arcane))
}
