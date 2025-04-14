// @copyright André Trettin

import SwiftUI

#if os(iOS) || os(visionOS)

// by klaytonb
// https://forums.developer.apple.com/forums/thread/699111?answerId=740437022#740437022
import Combine

extension Publishers {
    @MainActor
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .map { $0.keyboardHeight }
        let willHide = NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
        
        return MergeMany(willShow, willHide)
            .eraseToAnyPublisher()
    }
}

extension Notification {
    @MainActor
    var keyboardHeight: CGFloat {
        return (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
    }
}

struct KeyboardAvoiding: ViewModifier {
    @State private var keyboardActiveAdjustment: CGFloat = 0
    private let height: CGFloat
    public init(height: CGFloat) {
        self.height = height
    }
    
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: keyboardActiveAdjustment) {
                EmptyView().frame(height: 0)
            }
            .onReceive(Publishers.keyboardHeight) {
                self.keyboardActiveAdjustment = min($0, height)
            }
    }
}

#endif

public extension View {
    func keyboardAvoiding(height: CGFloat = 30) -> some View {
#if os(iOS) || os(visionOS)
        modifier(KeyboardAvoiding(height: height))
#else
        self
#endif
    }
}


