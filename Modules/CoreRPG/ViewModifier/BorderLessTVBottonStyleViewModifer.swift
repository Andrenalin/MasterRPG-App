// @copyright André Trettin

import SwiftUI

public extension View {
    func borderLessTVBottonStyle(notMac: Bool = false) -> some View {
        modifier(BorderLessTVBottonStyleViewModifer(notMac: notMac))
    }
}

struct BorderLessTVBottonStyleViewModifer: ViewModifier {
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

public extension View {
    func switchTVToggleStyle() -> some View {
        modifier(SwitchTVToggleStyleViewModifer())
    }
}

struct SwitchTVToggleStyleViewModifer: ViewModifier {
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content
            .toggleStyle(.switch)
#endif
    }
}
