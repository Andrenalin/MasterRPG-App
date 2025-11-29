// @copyright André Trettin

import SwiftUI

public extension View {
    func focusSectionAll() -> some View {
        modifier(FocusSectionViewModifier())
    }
    
    func prefersDefaultFocusAll(_ isFocused: Bool, in namespace: Namespace.ID) -> some View {
        modifier(PrefersDefaultFocusViewModifier(isFocused: isFocused, namespace: namespace))
    }
    
    func focusScopeAll(_ namespace: Namespace.ID) -> some View {
        modifier(FocusScopeViewModifier(namespace: namespace))
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

struct PrefersDefaultFocusViewModifier: ViewModifier {
    let isFocused: Bool
    let namespace: Namespace.ID
    
    func body(content: Content) -> some View {
#if os(tvOS) || os(macOS)
        content
            .prefersDefaultFocus(isFocused, in: namespace)
#else
        content
#endif
    }
}

struct FocusScopeViewModifier: ViewModifier {
    let namespace: Namespace.ID
    
    func body(content: Content) -> some View {
#if os(tvOS) || os(macOS)
        content
            .focusScope(namespace)
#else
        content
#endif
    }
}
