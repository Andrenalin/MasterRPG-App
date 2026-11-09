// @copyright André Trettin

import CoreRPG
import Foundation
import TableRPG

extension PlayerController {
    func handleTable(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        return try await answerHeldItem(
            model,
            reveal: { try await revealTable(model) },
            didReveal: { gameModel.setGameUpdateType(.table) },
            store: {
                try await root.tableRoot.tableGameControllable.receiveTable(
                    itemId: model.data.id,
                    data: model.data,
                    makeCurrent: false
                )
            }
        )
    }

    /// Makes the revealed Table current. The co-located game-master player receives its own Table
    /// reveal as a reference. Its persistent Table is the canonical source, so an exact-version
    /// reference can be selected directly without the session-availability cache used by remote
    /// players. Otherwise the local echo asks for bytes, but that upstream request is correctly
    /// suppressed to avoid a master/local-player loop and the master UI never changes.
    private func revealTable(_ model: GameNetworkModel) async throws -> Bool {
        if gameModel.asGameMaster,
           model.sender.isMaster,
           model.data.data == nil,
           model.data.version != 0,
           await root.tableRoot.gameControllable.networkVersion(for: model.data.id) == model.data.version,
           await root.tableRoot.gameControllable.setCurrent(itemId: model.data.id) {
            return true
        }
        return try await root.tableRoot.tableGameControllable.receiveTable(
            itemId: model.data.id,
            data: model.data,
            makeCurrent: true
        )
    }
}
