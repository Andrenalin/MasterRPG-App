// @copyright André Trettin

#if !os(tvOS)
import CharacterRPG
import CoreRPG
import SwiftUI

/// A player's own list: the companions it brings along. Each enabled one gets a player pin
/// that this player moves, unless the game master hands it to someone else.
struct CompanionsList: View {
    let root: GameRoot
    let model: TablePlayersModel

    var body: some View {
        let player = root.gameModel.gamePlayer
        let roster = root.gameModel.gameRoster.players

        List {
            Section {
                if player.companions.isEmpty {
                    Text("No companions", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(player.companions) { companion in
                        CompanionRow(root: root, model: model, companion: companion, roster: roster)
                    }
                    .onDelete(perform: model.remove(atOffsets:))
                }

                if player.companions.count < PlayerGameModel.maximumCompanions {
                    Button(action: model.startPicking) {
                        Label {
                            Text("Add Companions", bundle: .module)
                        } icon: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
            } header: {
                Text("Companions at the Table", bundle: .module)
            } footer: {
                Text("Each enabled companion gets a player pin on every shown map, which you move. The game master can let others move it.", bundle: .module)
            }
        }
        .listStyle(.inset)
        .themedListSurface()
    }
}

#endif
