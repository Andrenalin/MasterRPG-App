// @copyright André Trettin

import SwiftUI

#if os(iOS) || os(visionOS)

// by klaytonb
// https://forums.developer.apple.com/forums/thread/699111?answerId=740437022#740437022

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
            // Replaces a merged Combine publisher of the two keyboard
            // notifications with two independent async sequences — SwiftUI's
            // `.task` cancels both automatically on disappear. See
            // CODE_AUDIT_9 §4.4.
            .task {
                for await notification in NotificationCenter.default.notifications(named: UIApplication.keyboardWillShowNotification) {
                    keyboardActiveAdjustment = min(notification.keyboardHeight, height)
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIApplication.keyboardWillHideNotification) {
                    keyboardActiveAdjustment = min(0, height)
                }
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


