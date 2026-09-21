// @copyright André Trettin

import SwiftUI

public extension View {
    func navigationVisibility(_ visible: Bool = true) -> some View {
        modifier(NavigationVisibilityViewModifier(visible: visible))
    }
}

struct NavigationVisibilityViewModifier: ViewModifier {
    let visible: Bool
    
    func body(content: Content) -> some View {
#if os(iOS) || os(visionOS)
        content
            .toolbarVisibility(visible ? .visible : .hidden, for: .navigationBar)
#else
        content
#endif
    }
}
