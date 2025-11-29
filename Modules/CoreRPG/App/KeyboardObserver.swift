// @copyright André Trettin

import Combine
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
            .onReceive(keyboardPublisher) { isShowing in
                keyboardShowHandler(isShowing)
            }
#else
        content
#endif
    }
    
#if os(iOS)
    var keyboardPublisher: AnyPublisher<Bool, Never> {
        Publishers
            .Merge(
                NotificationCenter
                    .default
                    .publisher(for: UIResponder.keyboardWillShowNotification)
                    .map { _ in true },
                NotificationCenter
                    .default
                    .publisher(for: UIResponder.keyboardWillHideNotification)
                    .map { _ in false })
            .eraseToAnyPublisher()
    }
#endif
}
