// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Simple toggle button for iOS, iPadOS, and tvOS (show/hide only).
struct GameMainTabToggleButtonView: View {
    /// Grows with Dynamic Type instead of a fixed 24 pt. See CODE_AUDIT_18 §8.3.
    @ScaledMetric private var iconSize: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let isMaster: Bool
    @Binding var isShown: Bool

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                isShown.toggle()
            }
        } label: {
            Image(systemName: NetworkModules.game.icon)
#if os(iOS)
                .frame(height: iconSize)
#elseif os(tvOS)
                // tvOS has no selected button style; the filled symbol shows the state.
                .symbolVariant(isShown ? .fill : .none)
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
