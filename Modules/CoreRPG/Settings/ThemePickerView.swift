// @copyright André Trettin

import SwiftUI

public struct ThemePickerView: View {
    public init() {}

    @Environment(AppSettingsModel.self) private var settingsModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    if !settingsModel.recentThemeIDs.isEmpty {
                        ThemeGridSection(
                            title: LocalizedStringResource("Recent", bundle: .module),
                            themeIDs: settingsModel.recentThemeIDs
                        )
                    }

                    ThemeGridSection(
                        title: LocalizedStringResource("Presets", bundle: .module),
                        themeIDs: AppThemeID.allCases
                    )
                }
                .padding()
            }
            .themedSurface()
            .navigationTitle(Text("Choose Theme", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    ThemePickerView()
        .environment(AppSettingsModel.previewFixture(appThemeID: .midnight))
}
