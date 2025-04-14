// @copyright André Trettin

import SwiftUI

public extension View {
    func topSafeAreaPadding(_ topMargin: Bool = true) -> some View {
        modifier(SafeHeaderMarginViewModifier(topMargin: topMargin))
    }
}

struct SafeHeaderMarginViewModifier: ViewModifier {
    let topMargin: Bool
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.wideMode) private var wideMode

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.top, margin)
    }
    
    private var margin: CGFloat {
        var safeMargin = safeAreaInsets.top
#if os(iOS)
        let tabBarHeight = UITabBarController().tabBar.frame.size.height
        if wideMode != .small && topMargin {
            safeMargin += tabBarHeight + 4
        }
#elseif os(macOS)
        safeMargin += 8
#endif
        return safeMargin
    }
}
