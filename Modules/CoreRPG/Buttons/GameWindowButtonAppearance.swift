// @copyright André Trettin

import SwiftUI

public struct GameWindowButtonAppearance: ViewModifier {
    public init(module: NetworkModules, isWindowPresented: Bool) {
        self.module = module
        self.isWindowPresented = isWindowPresented
    }
    
    let module: NetworkModules
    let isWindowPresented: Bool

    @Environment(\.appTheme) private var theme

    public func body(content: Content) -> some View {
        let tint = theme.tint(for: module)
#if os(visionOS)
        content
            .buttonStyle(.bordered)
            // `.bordered` defaults to a capsule border and hover shape; these buttons are round.
            .buttonBorderShape(.circle)
            .contentShape(.hoverEffect, .circle)
            .tint(isWindowPresented ? tint : .accentColor)
            .background(
                isWindowPresented ? tint.opacity(0.35) : Color.clear,
                in: .circle
            )
#else
        let glass: Glass = if isWindowPresented {
            .regular.tint(tint.opacity(0.7)).interactive()
        } else {
            .regular.interactive()
        }

        content
            .buttonStyle(.plain)
            .glassEffect(glass, in: .circle)
#endif
    }
}
