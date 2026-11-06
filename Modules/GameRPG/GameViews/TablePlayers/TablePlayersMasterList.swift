// @copyright André Trettin

#if !os(tvOS)
import CharacterRPG
import CoreRPG
import SwiftUI

/// The connected players with their "send updates" switch, the Characters at the table, and
/// what the Logs window shows: the sharing options, the SharePlay attachments and the messages.
struct TablePlayersList: View {
    let root: GameRoot
    let model: TablePlayersModel

    var body: some View {
        let gameModel = root.gameModel
        let connected = gameModel.gameRoster.players
        let tablePlayers = gameModel.tablePlayers

        List {
            Section {
                if connected.isEmpty {
                    Text("No players connected", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(connected) { player in
                        ConnectedPlayerRow(root: root, player: player)
                    }
                }
            } header: {
                Text("Connected", bundle: .module)
            }

            let companions = connected.filter { $0.type == .player }.flatMap { player in
                player.companions.map { CompanionEntry(owner: player, companion: $0) }
            }
            if !companions.isEmpty {
                Section {
                    ForEach(companions) { entry in
                        MasterCompanionRow(root: root, owner: entry.owner, companion: entry.companion, roster: connected)
                    }
                } header: {
                    Text("Companions", bundle: .module)
                } footer: {
                    Text("Characters the players bring along. Each is moved by its player unless you choose otherwise.", bundle: .module)
                }
            }

            Section {
                if tablePlayers.isEmpty {
                    Text("No Characters at the table", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tablePlayers) { tablePlayer in
                        TablePlayerRow(root: root, model: model, tablePlayer: tablePlayer, roster: connected)
                    }
                    .onDelete(perform: model.remove(atOffsets:))
                }

                Button(action: model.startPicking) {
                    Label {
                        Text("Add Characters", bundle: .module)
                    } icon: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            } header: {
                Text("Characters at the Table", bundle: .module)
            } footer: {
                Text("Each enabled Character gets a player pin on every shown map, like a joined player. A player who joins with the same Character takes over its pin.", bundle: .module)
            }

            LogSections(logController: root.logGameController)
        }
        .listStyle(.inset)
        .themedListSurface()
    }
}

struct CompanionEntry: Identifiable {
    let owner: PlayerGameModel
    let companion: TablePlayerModel

    var id: UUID { companion.id }
}

#endif
