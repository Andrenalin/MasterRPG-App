// @copyright André Trettin

import CoreRPG
import SwiftUI

public typealias ColorSchemeView = CoreRPG.ColorSchemeView

#Preview("System color scheme") {
    ColorSchemeView(colorScheme: .system)
        .padding()
}

#Preview("Dark color scheme") {
    ColorSchemeView(colorScheme: .dark)
        .padding()
}

#Preview("Light color scheme") {
    ColorSchemeView(colorScheme: .light)
        .padding()
}
