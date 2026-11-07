// @copyright André Trettin

import CoreRPG
import Foundation
import TableRPG

// MARK: - Table Messages

extension MasterController {
    func handleTable(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.type != .update else { return nil }

        if model.subType == .ok {
            let currentVersion = await root.tableRoot.gameControllable.networkVersion(for: model.data.id)
            guard model.data.version != 0, model.data.version == currentVersion else { return nil }
            root.tableRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }

        switch model.type {
        case .reveal, .store:
            return try await root.tableRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            return nil
        }
    }
}
