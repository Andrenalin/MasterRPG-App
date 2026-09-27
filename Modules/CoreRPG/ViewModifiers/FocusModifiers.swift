// @copyright André Trettin

import SwiftUI

public extension View {
    func focusSectionAll() -> some View {
        modifier(FocusSectionViewModifier())
    }
    
}

struct FocusSectionViewModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(tvOS) || os(macOS)
        content
            .focusSection()
#else
        content
#endif
    }
}
