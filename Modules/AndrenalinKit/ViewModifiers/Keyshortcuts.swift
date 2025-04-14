// @copyright André Trettin

#if !os(tvOS)

    import SwiftUI

    public extension View {
            @ViewBuilder
        func keyActionShortCut(key: KeyEquivalent?, modifiers: EventModifiers = [.shift, .command], action: @escaping () -> Void) -> some View {
            if let key {
                modifier(KeyActionShortCutViewModifier(key: key, modifiers: modifiers, action: action))
            } else {
                self
            }
        }
    }

    struct KeyActionShortCutViewModifier: ViewModifier {
        let key: KeyEquivalent
        let modifiers: EventModifiers
        let action: () -> Void

        func body(content: Content) -> some View {
            content.overlay {
                Button(action: action) {
                    Color.clear
                }
                .borderLessTVBottonStyle()
                .keyboardShortcut(key, modifiers: modifiers)
            }
        }
    }

#endif
