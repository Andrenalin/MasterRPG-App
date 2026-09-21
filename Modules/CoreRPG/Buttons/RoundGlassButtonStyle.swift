// @copyright André Trettin

import SwiftUI

public extension View {
    func selectedRoundButton(title: String, module: NetworkModules, isSelected: Bool) -> some View {
        modifier(SelectedRoundButtonViewModifier(title: title, module: module, isSelected: isSelected))
    }
}

struct SelectedRoundButtonViewModifier: ViewModifier {
    let title: String
    let module: NetworkModules
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .imageScale(.large)
            .padding(8)
            .contentShape(.circle)
            .modifier(
                GameWindowButtonAppearance(
                    module: module,
                    isWindowPresented: isSelected
                )
            )
            .help(title)
            .accessibilityLabel(title)
    }
}
