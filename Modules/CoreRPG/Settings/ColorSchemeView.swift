// @copyright André Trettin

import SwiftUI

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
        case .light: "Light"
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
