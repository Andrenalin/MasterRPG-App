// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameSetupTipCard: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text("Ready table, happy party", bundle: .module)
                    .bold()
                Text(
                    "Choose your role first. MasterRPG will keep your last adventure or character ready for the next session.",
                    bundle: .module
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(theme.tint(for: .adventure))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            theme.panelColor.opacity(0.82),
            in: .rect(cornerRadius: 20)
        )
    }
}

#Preview("Shared · Tip") {
    GameSetupTipCard()
        .padding()
}
