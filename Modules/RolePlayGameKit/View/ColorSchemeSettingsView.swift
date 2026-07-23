// @copyright André Trettin

import CoreRPG
import SwiftUI

public typealias ColorSchemeSettingsView = CoreRPG.ColorSchemeSettingsView

#Preview {
    ColorSchemeSettingsView()
        .environment(AppSettingsModel())
        .environment(\.locale, Locale(identifier: "de"))
}
