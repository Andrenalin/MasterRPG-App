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

    func masterReceived(data: Data?, for connectionId: ConnectionController.ID) async {
        // Before anything is decoded: one connection cannot make this device decode an
        // unbounded number of large frames. See CODE_AUDIT_26 §6.6.
        if let data, await !model.admitsLanFrame(byteCount: data.count, from: connectionId) {
            Logger.networking.error("GameNetworkController: Dropped a \(data.count, privacy: .public) byte frame from \(connectionId, privacy: .public): over the inbound byte budget")
            return
        }
        guard let gameData = await GameNetworkModel.decodedOffMain(of: data) else {
            Logger.networking.debug("GameNetworkController: Master Received invalid game data from \(connectionId)")
            await handleUndecodable(data, from: connectionId)
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
            if gameData.isPlayerGroupEvent, await model.masterDelegate?.mayRelay(gameData, origin: origin) != false {
                // A Dice roll, a moved pin or a Space transform is for the whole group: the
                // other local-network players and the SharePlay session get it from here.
                // Forward the received bytes as they are when their size matches the decoded
                // payload: re-encoding the decoded model doubled peak memory and CPU per
                // relayed event (CODE_AUDIT_17 §7.2). A frame much larger than its payload
                // carries ignored padding, which would be amplified to every player, so it is
                // re-encoded (dropping unknown keys) instead. See CODE_AUDIT_18 §6.2.
                let payloadByteCount = gameData.data.data?.count ?? 0
                let relayed: any MessageMapper = if let data,
                    Self.relayForwardsReceivedBytes(frameByteCount: data.count, payloadByteCount: payloadByteCount) {
                    PreEncodedMessage(bytes: data)
                } else {
                    gameData
                }
                await model.masterStore?.sendResponse(data: relayed, except: connectionId)
                // `sendDataReportingLoss` is itself `@MainActor` — `await` alone hops there.
                await sharePlayStore.sendDataReportingLoss(gameData)
            }
            await model.masterDelegate?.receivedAccepted(gameData, origin: origin)
        }
    }
}
