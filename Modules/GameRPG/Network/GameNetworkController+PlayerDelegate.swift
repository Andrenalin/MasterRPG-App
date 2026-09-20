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
        guard let gameData = GameNetworkModel.decodeData(of: data) else {
            Logger.networking.debug("GameNetworkController: Player received invalid game data")
            return
        }
        if proxy {
            await model.playerProxyDelegate?.receivedProxy(gameData)
        } else {
            await model.playerDelegate?.received(gameData)
        }
    }
}
