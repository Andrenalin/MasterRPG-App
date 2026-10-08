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
                // Forward the received bytes as they are when their size matches the decoded
                // payload: re-encoding the decoded model doubled peak memory and CPU per
                // relayed presentation (CODE_AUDIT_17 §7.2). A frame much larger than its
                // payload carries ignored padding, which would be amplified to every player,
                // so it is re-encoded (dropping unknown keys) instead. See CODE_AUDIT_18 §6.2.
                let payloadByteCount = gameData.data.data?.count ?? 0
                let relayed: any MessageMapper = if let data,
                    Self.relayForwardsReceivedBytes(frameByteCount: data.count, payloadByteCount: payloadByteCount) {
                    PreEncodedMessage(bytes: data)
                } else {
                    gameData
                }
                let relayedByteCount = data.map { min($0.count, payloadByteCount / 3 * 4 + Self.relayFrameOverheadAllowance) } ?? payloadByteCount
                guard await relayAdmission.admitBytes(relayedByteCount, from: gameData.sender.id) else {
                    Logger.networking.error("GameNetworkController: Relay byte budget exceeded by \(gameData.sender.id, privacy: .public); not relaying")
                    await model.masterDelegate?.received(gameData, origin: origin)
                    return
                }
                await model.masterStore?.sendResponse(data: relayed, except: connectionId)
                let useFileJournal = fileJournal || gameData.usesFileJournal
                // `sendDataReportingLoss` is itself `@MainActor` — `await` alone hops there,
                // no `MainActor.run` wrapper needed.
                await sharePlayStore.sendDataReportingLoss(gameData, fileJournal: useFileJournal)
            }
            await model.masterDelegate?.received(gameData, origin: origin)
        }
    }
}
