// @copyright André Trettin

import CoreRPG
import Foundation
import SpaceRPG

extension PlayerController {
    func handleSpace(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard !model.isAcknowledgement else { return nil }

        if model.isPlayerGroupEvent {
            // Another player moved the Space.
            applySpaceTransform(model)
            return nil
        }

        // Spaces come from the game master only; a player shows one through the master.
        guard model.sender.isMaster else { return nil }

        return try await handleFileBackedMessage(
            model,
            access: root.spaceRoot.fileBackedAccess,
            versionlessSubTypes: [.spaceTransform],
            // The game screen opens the immersive space itself when it shows the space
            // module — see GameRootViewer's reveal handler.
            didReveal: { _ in gameModel.setGameUpdateType(.space) },
            handleOtherUpdate: { model in
                if model.subType == .spaceTransform {
                    applySpaceTransform(model)
                } else if await root.spaceRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    gameModel.setGameUpdateType(.space)
                }
            }
        )
    }

    /// Applies a transform of the master's version of the Space. A player's transform also
    /// needs Space sharing to be on.
    private func applySpaceTransform(_ model: GameNetworkModel) {
        guard model.sender.isMaster || root.gameModel.gameControl.features.spaceSharing else { return }
        let baseline = root.spaceRoot.spaceGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        )
        guard baseline == nil || baseline == model.data.effectiveAssetVersion else { return }
        _ = root.spaceRoot.spaceGameControllable.applySpaceTransform(
            data: model.data,
            counter: model.counter,
            timestamp: model.timestamp
        )
    }
}
