// @copyright André Trettin

import CoreRPG
import Foundation
import TableRPG

extension PlayerController {
    func handleTable(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        switch model.type {
        case .reveal:
            // The co-located game-master player receives its own Table reveal
            // as a reference. Its persistent Table is the canonical source, so
            // an exact-version reference can be selected directly without the
            // session-availability cache used by remote players. Otherwise the
            // local echo asks for bytes, but that upstream request is correctly
            // suppressed to avoid a master/local-player loop and the master UI
            // never changes.
            if await gameModel.asGameMaster,
               model.sender.isMaster,
               model.data.data == nil,
               model.data.version != 0,
               await root.tableRoot.gameControllable.networkVersion(for: model.data.id) == model.data.version,
               await root.tableRoot.gameControllable.setCurrent(itemId: model.data.id) {
                await gameModel.setGameUpdateType(.table)
                return await response(for: model, isSuccess: true, requestData: false)
            }
            if try await root.tableRoot.tableGameControllable.receiveTable(
                itemId: model.data.id,
                data: model.data,
                makeCurrent: true
            ) {
                await gameModel.setGameUpdateType(.table)
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            if try await root.tableRoot.tableGameControllable.receiveTable(
                itemId: model.data.id,
                data: model.data,
                makeCurrent: false
            ) {
                return await response(for: model, isSuccess: true, requestData: false)
            }
            return await response(for: model, isSuccess: true, requestData: true)
        case .update:
            return nil
        }
    }
}
