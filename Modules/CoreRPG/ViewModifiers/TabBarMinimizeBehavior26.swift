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
        content.backgroundExtensionEffect()
    }
}

private struct TabBarMinimizeBehavior26ViewModifier: ViewModifier {
    let behavior: TabBarMinimizeBehavior26
    
    func body(content: Content) -> some View {
#if os(iOS)
        content.tabBarMinimizeBehavior(behavior.tabBarMinimizeBehavior)
#else
        content
#endif
    }
}


public struct GlassEffectContainerView<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder var content: Content

    public var body: some View {
#if os(visionOS)
        content
#else
        GlassEffectContainer {
            content
        }
#endif
    }
}

/// A type alias for GlassEffectContainerView that automatically handles visionOS platform differences.
/// Use this instead of wrapping GlassEffectContainer in #if !os(visionOS) checks.
public typealias GlassEffectContainerAll = GlassEffectContainerView

#Preview {
    GlassEffectContainerView {
        Text(verbatim: "Glass content")
            .padding()
    }
}
