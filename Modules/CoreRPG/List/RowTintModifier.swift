// @copyright André Trettin

import SwiftUI

public extension View {
    func listTintStyle() -> some View {
        modifier(ListStyleModifier())
    }
}

struct ListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listItemTint(Color.accentColor)
        #if os(macOS)
            .listStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
        #else
            .listStyle(.grouped)
        #endif
    }
}
