// @copyright André Trettin

import SwiftUI

public extension View {
    func selectedBorderedStype(isSelected: Bool) -> some View {
        modifier(SelectedBorderedButtonViewModifier(isSelected: isSelected))
    }
}

struct SelectedBorderedButtonViewModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
#if !os(visionOS) && !os(tvOS)
        if isSelected {
            content
                .buttonStyle(.borderedProminent)
        } else {
            content
                .buttonStyle(.bordered)
        }
#else
        content
#endif
    }
}
