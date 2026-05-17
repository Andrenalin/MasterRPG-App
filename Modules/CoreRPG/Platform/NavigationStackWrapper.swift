// @copyright André Trettin

import SwiftUI

public extension View {
    func managedNavigationStack(wrapping: Bool) -> some View {
        modifier(ManagedNavigationStackWrapper(wrapping: wrapping))
    }
}

struct ManagedNavigationStackWrapper: ViewModifier {
    let wrapping: Bool
    
    func body(content: Content) -> some View {
        if wrapping {
            ManagedNavigationStack {
                content
            }
        } else {
            content
        }
    }
}
