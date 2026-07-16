// @copyright André Trettin

import SwiftUI

public struct ColorSchemeSettingsView: View {
    public init() {}

    @Environment(AppSettingsModel.self) private var settingsModel

    public var body: some View {
        @Bindable var settingsModel = settingsModel
        
        SectionGroupEditorView {
            Picker(selection: $settingsModel.appColorScheme) {
                ForEach(AppSettingsModel.AppColorScheme.allCases) { colorScheme in
                    ColorSchemeView(colorScheme: colorScheme)
                        .tag(colorScheme)
                        .tint(.accentColor)
                }
            } label: {
                Text("Color Scheme", bundle: .module)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .tint(.accentColor)
            .labelsHidden()
        } header: {
            Text("Color Scheme", bundle: .module)
        }
    }
}

#Preview {
    ColorSchemeSettingsView()
        .environment(AppSettingsModel.previewFixture())
        .environment(\.locale, Locale(identifier: "de"))
}
