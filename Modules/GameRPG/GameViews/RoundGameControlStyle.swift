// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The round chrome of a floating game control: a large symbol on a circle. By default the
/// circle is glass (the quick dice and dice toggles); with a module it is the window button
/// look of the visionOS side menus. One place for what each menu used to copy.
/// See CODE_AUDIT_24 §9.13.
struct RoundGameControlStyle: ViewModifier {
    var module: NetworkModules?

    func body(content: Content) -> some View {
        if let module {
            content
                .imageScale(.large)
                .padding(8)
                .contentShape(.circle)
                .modifier(GameWindowButtonAppearance(module: module, isWindowPresented: false))
        } else {
#if os(tvOS) || os(visionOS)
            // visionOS has no 2D game screen, so no floating controls.
            content
#else
            content
                .buttonStyle(.plain)
                .imageScale(.large)
                .padding(8)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
#endif
        }
    }
}

extension View {
    /// Puts the round control chrome around a button. See `RoundGameControlStyle`.
    func roundGameControl(module: NetworkModules? = nil) -> some View {
        modifier(RoundGameControlStyle(module: module))
    }
}
