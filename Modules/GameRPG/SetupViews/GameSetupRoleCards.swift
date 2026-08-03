// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameSetupRoleCards: View {
    @Binding var selection: GameSetupRole

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    var body: some View {
        VStack(spacing: 16) {
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
                                if appSizeModel.mode == .regular {
                                    Text(role.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: appSizeModel.mode == .regular ? 120 : 80)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(selection == role ? nil : .secondary.opacity(0.35))
                        .accessibilityAddTraits(selection == role ? .isSelected : [])
                    }
                }
            }

            if appSizeModel.mode == .compact {
                Text(selection.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
            }
        }
    }
}

#Preview("Shared · Role cards") {
    @Previewable @State var role = GameSetupRole.previewPlayer

    GameSetupRoleCards(selection: $role)
        .padding()
        .setAppSizeMode()
}

