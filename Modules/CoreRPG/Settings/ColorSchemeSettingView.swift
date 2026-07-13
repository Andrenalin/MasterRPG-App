// @copyright André Trettin

import SwiftUI

#Preview("System") {
    ColorSchemeView(colorScheme: .system)
        .padding()
}

#Preview("Dark") {
    ColorSchemeView(colorScheme: .dark)
        .padding()
}

#Preview("Light") {
    ColorSchemeView(colorScheme: .light)
        .padding()
}

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

public struct ColorSchemeView: View {
    public init(colorScheme: AppSettingsModel.AppColorScheme) {
        self.colorScheme = colorScheme
    }

    let colorScheme: AppSettingsModel.AppColorScheme

    public var body: some View {
        Label {
            Text(text(for: colorScheme), bundle: .module)
        } icon: {
            Image(systemName: icon(for: colorScheme))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func text(for colorScheme: AppSettingsModel.AppColorScheme) -> LocalizedStringKey {
        switch colorScheme {
        case .system: "System"
        case .dark: "Dark"
        case .light:"Light"
        }
    }

    private func icon(for colorScheme: AppSettingsModel.AppColorScheme) -> String {
        switch colorScheme {
        case .system: "gear"
        case .dark: "circle.lefthalf.striped.horizontal.inverse"
        case .light: "circle.lefthalf.striped.horizontal"
        }
    }
}

#Preview {
    ColorSchemeSettingsView()
        .environment(AppSettingsModel())
        .environment(\.locale, Locale(identifier: "de"))
}
