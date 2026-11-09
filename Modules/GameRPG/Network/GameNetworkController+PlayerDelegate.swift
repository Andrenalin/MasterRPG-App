// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI
import GroupActivities

// MARK: - PlayerNetworkControllerDelegate

extension GameNetworkController: PlayerNetworkControllerDelegate {
    func playerLostMaster() async {
        if proxy {
            await model.playerProxyDelegate?.lostProxyConnection()
        } else {
            await model.playerDelegate?.lostConnection()
        }
    }

    func playerReady() async {
        if proxy {
            await model.playerProxyDelegate?.readyProxy()
        } else {
            await model.playerDelegate?.ready()
        }
    }

    func playerReceived(data: Data?) async {
        guard let gameData = await GameNetworkModel.decodedOffMain(of: data) else {
            Logger.networking.debug("GameNetworkController: Player received invalid game data")
            await handleUndecodable(data, from: nil)
            return
        }
        if proxy {
            await model.playerProxyDelegate?.receivedProxy(gameData)
        } else {
            await model.playerDelegate?.received(gameData)
        }
    }
}

// MARK: - Version mismatch

extension GameNetworkController {
    /// A frame that does not decode may come from another build of the app. The person at this
    /// device is told, and a peer that sent an envelope of another version is answered once
    /// with a minimal notice, so its owner is told as well. See CODE_AUDIT_Game_Shareplay §5.9.
    func handleUndecodable(_ data: Data?, from connectionId: ConnectionController.ID?) async {
        guard !proxy, let mismatch = GameVersionMismatch.detect(in: data) else { return }
        Logger.networking.error("GameNetworkController: Cannot read a message of another app version: \(String(describing: mismatch), privacy: .public)")
        if model.claimMismatchReport(mismatch) {
            if connectionId != nil {
                await model.masterDelegate?.incompatibleVersion(mismatch)
            } else {
                await model.playerDelegate?.incompatibleVersion(mismatch)
            }
        }
        guard case .peerWrites = mismatch else { return }
        if let connectionId {
            if model.claimVersionNotice(for: connectionId) {
                await model.masterStore?.sendResponse(data: GameVersionNotice(), id: connectionId)
            }
        } else if model.claimVersionNoticeToMaster() {
            await model.playerStore?.request(with: GameVersionNotice())
        }
    }
}
