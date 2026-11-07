// @copyright André Trettin

import CoreRPG
import Foundation
import SpaceRPG

// MARK: - Space Messages

extension MasterController {
    func handleSpace(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        try await handleFileBackedMessage(model, access: root.spaceRoot.fileBackedAccess) { model in
            if model.subType == .spaceTransform {
                await applySpaceTransformFromPlayer(model)
            }
        }
    }

    /// A player moved the Space: applied when it moved the master's version of it, and
    /// Space sharing is on.
    private func applySpaceTransformFromPlayer(_ model: GameNetworkModel) async {
        guard model.isPlayerGroupEvent,
              root.gameModel.gameControl.features.spaceSharing,
              root.spaceRoot.spaceGameControllable.isValidSpaceTransform(model.data)
        else { return }

        // The transform is for the master's version of the Space only.
        let masterId = root.gameModel.gameConfig.id
        let space = root.spaceRoot.spaceGameControllable
        let baseline = await root.spaceRoot.gameControllable.networkVersion(for: model.data.id)
        space.setMasterVersion(itemId: model.data.id, version: baseline, masterId: masterId)
        guard model.data.effectiveAssetVersion == baseline,
              gameModel.canApplySpaceTransform(
                  from: model.sender.id,
                  itemId: model.data.id,
                  version: baseline,
                  counter: model.counter
              ),
              space.applySpaceTransform(data: model.data, counter: model.counter, timestamp: model.timestamp)
        else { return }
        gameModel.recordSpaceTransform(
            from: model.sender.id,
            itemId: model.data.id,
            version: baseline,
            counter: model.counter
        )
    }
}
