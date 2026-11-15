// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import CharacterRPG

// MARK: - MasterNetworkProxyControllerDelegate

extension MasterController: MasterNetworkProxyControllerDelegate {
    func lostProxy(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Lost Proxy for \(connectionId, privacy: .public)")
        if let playerId = store.model.playerRoutes.remove(connectionId: connectionId) {
            gameModel.forget(playerId: playerId)
            lateAudioPlayers.remove(playerId)
        }
    }

    func readyProxy(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Proxy Ready for \(connectionId, privacy: .public)")
        await replayCurrentPresentation(to: .proxy(connectionId))
        guard let characterId = root.gameModel.gamePlayer.characterId else { return }
        // Cancellation ends the replay; any other failure only skips the character and is logged.
        // `try?` made the two indistinguishable and the replay went on to send.
        // See CODE_AUDIT_Game_Shareplay §3.9.
        let data: NetworkCodableDataType
        do {
            data = try await root.characterRoot.gameControllable.createGameData(for: characterId)
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            Logger.networking.error("MasterController: Cannot export the proxy host character \(characterId, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            return
        }
        await send(
            type: .update,
            subtype: .store,
            updated: data,
            connectionId: connectionId,
            authoritativeMaster: true
        )
    }

    func receivedServerProxy(_ model: GameNetworkModel, connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Proxy Received \(model.counter, privacy: .public)/\(model.proxyCounter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        await received(model, origin: .proxy(connectionId))
    }
}
