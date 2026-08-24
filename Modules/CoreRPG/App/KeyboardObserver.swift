// @copyright André Trettin

import SwiftUI

public extension View {
    func onKeyboardShow(handler: @escaping (Bool) -> Void) -> some View {
        modifier(KeyboardObserverViewModifier(keyboardShowHandler: handler))
    }
}

struct KeyboardObserverViewModifier: ViewModifier {
    let keyboardShowHandler: (Bool) -> Void

    func body(content: Content) -> some View {
#if os(iOS)
        content
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                    keyboardShowHandler(true)
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification) {
                    keyboardShowHandler(false)
                }
            }
#else
        content
#endif
    }
}
