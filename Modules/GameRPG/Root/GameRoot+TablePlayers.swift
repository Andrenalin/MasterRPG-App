// @copyright André Trettin

import AdventureRPG
import CoreRPG
import Foundation

extension GameRoot {
    /// Replaces the game master's table players: saves them to the adventure and gives the
    /// enabled ones player pins (or takes the pins of the others away) on every game map.
    func updateTablePlayers(_ tablePlayers: [TablePlayerModel]) {
        guard gameModel.gameConfig.isMaster, gameModel.tablePlayers != tablePlayers else { return }
        gameModel.tablePlayers = tablePlayers
        if let adventureId = gameModel.gameConfig.master.adventureId {
            adventureRoot.adventureGameControllable.saveTablePlayers(tablePlayers, for: adventureId)
        }
        let masterController = gameModel.masterController
        Task {
            await masterController?.resetPlayers()
        }
    }

    /// The panel's model; its closures hold the root weakly, never a view.
    func makeTablePlayersModel() -> TablePlayersModel {
        TablePlayersModel { [weak self] in
            self?.gameModel.tablePlayers ?? []
        } update: { [weak self] tablePlayers in
            self?.updateTablePlayers(tablePlayers)
        }
    }
}
