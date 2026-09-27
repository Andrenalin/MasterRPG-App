// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

extension View {
    nonisolated public func inspectorAll<V>(isPresented: Binding<Bool>, @ViewBuilder content: () -> V) -> some View where V : View {
#if os(tvOS) || os(visionOS)
        self
#else
        inspector(isPresented: isPresented, content: content)
#endif
    }
    
    nonisolated public func glassEffectAll() -> some View {
#if os(visionOS)
        self
#else
        glassEffect()
#endif
    }

#if !os(visionOS)
    nonisolated public func glassEffectAll(_ style: Glass) -> some View {
        glassEffect(style)
    }

    nonisolated public func glassEffectAll<S>(_ style: Glass, in shape: S) -> some View where S : Shape {
        glassEffect(style, in: shape)
    }
#endif

    /// Applies keyboard shortcut on platforms that support it (excludes tvOS)
    nonisolated public func keyboardShortcutAll(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
#if os(tvOS)
        self
#else
        keyboardShortcut(key, modifiers: modifiers)
#endif
    }

    /// Applies keyboard shortcut on platforms that support it (excludes tvOS)
#if !os(tvOS)
    nonisolated public func keyboardShortcutAll(_ shortcut: KeyboardShortcut) -> some View {
        keyboardShortcut(shortcut)
    }
#else
    nonisolated public func keyboardShortcutAll(_ shortcut: Never) -> some View {
        self
    }
#endif

    /// Applies context menu on platforms that support it (excludes tvOS)
    @ViewBuilder
    nonisolated public func contextMenuAll<M>(@ViewBuilder menuItems: () -> M) -> some View where M : View {
#if os(tvOS)
        self
#else
        contextMenu(menuItems: menuItems)
#endif
    }

    nonisolated public func navigationBarTitleDisplayModeAll(_ displayMode: TitleDisplayModeAll) -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(displayMode.mode)
#else
        self
#endif

    }

}

public enum TitleDisplayModeAll : Sendable {
    case automatic
    case inline
    case large
    
#if os(iOS)
    var mode: NavigationBarItem.TitleDisplayMode {
        switch self {
        case .automatic: .automatic
        case .inline: .inline
        case .large: .large
        }
    }
#endif

}
