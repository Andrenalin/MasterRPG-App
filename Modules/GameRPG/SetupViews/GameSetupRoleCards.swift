// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameSetupRoleCards: View {
    @Binding var selection: GameSetupRole

    var body: some View {
        Grid {
            GridRow {
                ForEach(GameSetupRole.allCases) { role in
                    Button {
                        selection = role
                    } label: {
                        VStack {
                            Image(systemName: role.systemImage)
                                .font(.title)
                            Text(role.title)
                                .bold()
                            Text(role.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selection == role ? nil : .secondary.opacity(0.35))
                    .accessibilityAddTraits(selection == role ? .isSelected : [])
                }
            }
        }
    }
}

#Preview("Shared · Role cards") {
    @Previewable @State var role = GameSetupRole.previewPlayer

    GameSetupRoleCards(selection: $role)
        .padding()
}

