// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI
import GroupActivities

// MARK: - MasterNetworkControllerDelegate

extension GameNetworkController: MasterNetworkControllerDelegate {
    func masterLostPlayer(with connectionId: ConnectionController.ID) async {
        if proxy {
            await model.masterProxyDelegate?.lostProxy(for: connectionId)
        } else {
            await model.masterDelegate?.lostPlayer(for: connectionId)
        }
    }

    func masterReady(for connectionId: ConnectionController.ID) async {
        if proxy {
            await model.masterProxyDelegate?.readyProxy(for: connectionId)
        } else {
            await model.masterDelegate?.ready(for: .direct(connectionId))
        }
    }

    func masterReceived(data: Data?, for connectionId: ConnectionController.ID, fileJournal: Bool) async {
        guard let gameData = await GameNetworkModel.decodedOffMain(of: data) else {
            Logger.networking.debug("GameNetworkController: Master Received invalid game data from \(connectionId)")
            return
        }
        if proxy {
            // Don't resend in proxy mode — would cause an endless relay loop
            await model.masterProxyDelegate?.receivedServerProxy(gameData, connectionId: connectionId)
        } else {
            let origin = GameMessageOrigin.direct(connectionId)
            guard await model.masterDelegate?.accepts(gameData, origin: origin) == true else {
                Logger.networking.debug("GameNetworkController: Rejected unauthenticated LAN message from \(connectionId)")
                return
            }
            if Self.shouldRelayToLAN(gameData), await relayAdmission.admit(gameData) {
                // Forward the received bytes as they are: re-encoding the decoded model doubled
                // peak memory and CPU per relayed presentation. See CODE_AUDIT_17 §7.2.
                let relayed: any MessageMapper = data.map { PreEncodedMessage(bytes: $0) } ?? gameData
                await model.masterStore?.sendResponse(data: relayed, except: connectionId)
                let useFileJournal = fileJournal || gameData.usesFileJournal
                // `sendData` is itself `@MainActor` (and `@discardableResult`) — `await`
                // alone hops there, no `MainActor.run` wrapper needed.
                await sharePlayStore.sendData(gameData, fileJournal: useFileJournal)
            }
            await model.masterDelegate?.received(gameData, origin: origin)
        }
    }
}
