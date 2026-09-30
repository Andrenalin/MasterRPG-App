// @copyright André Trettin

import SwiftUI

public extension View {
    func borderLessTVButtonStyle(notMac: Bool = false) -> some View {
        modifier(BorderLessTVButtonStyleViewModifier(notMac: notMac))
    }
}

struct BorderLessTVButtonStyleViewModifier: ViewModifier {
    let notMac: Bool
    
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#elseif os(macOS)
        content
            .applyIf(!notMac) {
                $0.buttonStyle(.borderless)
            }
#else
        content
            .buttonStyle(.borderless)
#endif
    }
}

