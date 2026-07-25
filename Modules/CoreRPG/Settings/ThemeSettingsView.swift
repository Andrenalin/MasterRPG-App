// @copyright André Trettin

import SwiftUI

public struct ThemeSettingsView: View {
    public init() {
        self._isPickerPresented = .constant(false)
    }

    public init(isPickerPresented: Binding<Bool>) {
        self._isPickerPresented = isPickerPresented
    }

    @Environment(AppSettingsModel.self) private var settingsModel
    @Environment(\.appTheme) private var theme

    @Binding private var isPickerPresented: Bool

    public var body: some View {
        @Bindable var settingsModel = settingsModel
        
        SectionGroupEditorView {
            #if os(iOS)
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
            #endif
            
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
            .accessibilityIdentifier("settings.theme.choose")
            .accessibilityLabel(Text("Theme", bundle: .module))
            .accessibilityValue(Text(settingsModel.appThemeID.localizedName))
        } header: {
            Text("Theme", bundle: .module)
        } footer: {
            Text("Themes change app surfaces and module colors without changing your photos, maps, or documents.", bundle: .module)
        }
    }

    private func presentPicker() {
        isPickerPresented = true
    }
}

#Preview {
    @Previewable @State var isPickerPresented = false

    List {
        ThemeSettingsView(isPickerPresented: $isPickerPresented)
    }
    .environment(AppSettingsModel.previewFixture(appThemeID: .arcane))
}
