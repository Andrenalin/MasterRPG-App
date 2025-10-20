// @copyright André Trettin

import SwiftUI

public enum AppSizeMode {
    case compact
    case regular
}

public extension View {
    func setAppSizeMode() -> some View {
        modifier(HorizontalSizeViewModifier())
    }
}

public extension EnvironmentValues {
#if os(iOS)
    @Entry var appSizeMode: AppSizeMode = .compact
#else
    @Entry var appSizeMode: AppSizeMode = .regular
#endif
}

struct HorizontalSizeViewModifier: ViewModifier {
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    func body(content: Content) -> some View {
        content
#if os(iOS)
            .environment(\.appSizeMode, mode)
#endif
    }
    
#if os(iOS)
    var mode: AppSizeMode {
        horizontalSizeClass == .compact ? .compact : .regular
    }
#endif
    
}
