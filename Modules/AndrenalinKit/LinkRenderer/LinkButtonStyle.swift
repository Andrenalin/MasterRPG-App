// @copyright André Trettin

import SwiftUI

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.thinMaterial)
#if !os(macOS)
            .hoverEffect(.highlight)
#endif
            .clipShape(.rect(cornerRadius: 4, style: .continuous))
#if os(visionOS)
            .hoverEffect { effect, isActive, _ in
                effect.scaleEffect(isActive ? 1.2 : 1.0)
            }
#endif
    }
}
