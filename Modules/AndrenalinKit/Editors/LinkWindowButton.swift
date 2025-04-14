// @copyright André Trettin

import SwiftUI

public struct LinkWindowButton: View {
    public init(type: NetworkModules) {
        self.type = type
    }
    
    let type: NetworkModules

    @Environment(\.wideMode) private var wideMode
#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif

    public var body: some View {
        if wideMode != .small {
            Button {
                withAnimation {
#if !os(tvOS)
                    openWindow(id: type.linkWindowId)
#endif
                }
            } label: {
                Image(systemName: type.icon)
            }
        }
    }
}

#Preview {
    LinkWindowButton(type: .dice)
}
