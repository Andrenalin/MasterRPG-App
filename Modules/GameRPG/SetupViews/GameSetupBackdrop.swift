// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameSetupBackdrop: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            theme.backgroundGradient

            if !reduceTransparency {
                Circle()
                    .fill(theme.tint(for: .adventure).opacity(0.18))
                    .containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: 0)
                    .blur(radius: 48)
                    .offset(x: -120, y: -220)

                Circle()
                    .fill(theme.tint(for: .dice).opacity(0.14))
                    .containerRelativeFrame(.horizontal, count: 4, span: 3, spacing: 0)
                    .blur(radius: 56)
                    .offset(x: 160, y: 300)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview("Shared · Backdrop") {
    GameSetupBackdrop()
}

