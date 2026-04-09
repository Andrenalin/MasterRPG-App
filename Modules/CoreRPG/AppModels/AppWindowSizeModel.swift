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

struct HorizontalSizeViewModifier: ViewModifier {
    @State private var model: AppWindowSizeModel = AppWindowSizeModel()
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    func body(content: Content) -> some View {
        content
            .environment(model)
#if os(iOS)
            .onChange(of: horizontalSizeClass, initial: true) {
                model.mode = mode
            }
#endif
    }
    
#if os(iOS)
    var mode: AppSizeMode {
        horizontalSizeClass == .compact ? .compact : .regular
    }
#endif
}

@MainActor @Observable public final class AppWindowSizeModel: Sendable {
#if os(iOS)
    public internal(set) var mode: AppSizeMode = .compact
#else
    public internal(set) var mode: AppSizeMode = .regular
#endif
}
