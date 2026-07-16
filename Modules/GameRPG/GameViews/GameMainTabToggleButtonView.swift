// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Simple toggle button for iOS, iPadOS, and tvOS (show/hide only).
struct GameMainTabToggleButtonView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let isMaster: Bool
    @Binding var isShown: Bool

    var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                isShown.toggle()
            }
        } label: {
            Image(systemName: NetworkModules.game.icon)
#if os(iOS)
                .frame(height: 24)
#endif
        }
        .selectedBorderedStype(isSelected: isShown)
        .accessibilityLabel(
            isShown
                ? Text("Hide game view", bundle: .module)
                : Text("Show game view inline", bundle: .module)
        )
    }
}

#Preview("Toggle (iOS/tvOS)") {
    GameMainTabToggleButtonView(isMaster: true, isShown: .constant(true))
        .padding()
        .background(.ultraThinMaterial)
}
