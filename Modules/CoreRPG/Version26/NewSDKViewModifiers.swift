// @copyright André Trettin

import SwiftUI

public extension View {
    func backgroundExtensionEffect26() -> some View {
        modifier(BackgroundExtensionEffect())
    }
    
    func tabBarMinimizeBehavior26(_ behavior: TabBarMinimizeBehavior26) -> some View {
        modifier(TabBarMinimizeBehavior26ViewModifier(behavior: behavior))
    }
}

public enum TabBarMinimizeBehavior26: Hashable, Sendable {
    case automatic
    case onScrollDown
    case onScrollUp
    case never
    
#if os(iOS)
    @available(iOS 26.0, *)
    var tabBarMinimizeBehavior: TabBarMinimizeBehavior {
        switch self {
        case .automatic: .automatic
        case .onScrollDown: .onScrollDown
        case .onScrollUp: .onScrollUp
        case .never: .never
        }
    }
#endif
}

private struct BackgroundExtensionEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
            content.backgroundExtensionEffect()
        } else {
            content
        }
    }
}

private struct TabBarMinimizeBehavior26ViewModifier: ViewModifier {
    let behavior: TabBarMinimizeBehavior26
    
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(behavior.tabBarMinimizeBehavior)
        } else {
            content
        }
#else
        content
#endif
    }
}


