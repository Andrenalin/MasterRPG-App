// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import MapRPG

// Split out of PlayerController+Map.swift — repair-request construction and
// pending-payload application. See CODE_AUDIT_Game §9.9.

extension PlayerController {
    func applyPendingMapContentUpdate(itemId: UUID) async -> Bool {
        guard let pending = gameModel.pendingMapContentUpdate(for: itemId) else { return false }
        guard gameModel.shouldApplyMapContentUpdate(
            itemId: itemId,
            counter: pending.counter
        ) else {
            gameModel.discardPendingMapContentUpdate(itemId: itemId)
            return false
        }
        guard await root.mapRoot.gameControllable.hasItem(id: itemId, version: 0),
              await hasMatchingMapAsset(pending.data),
              root.mapRoot.mapGameControllable.applyMapContentUpdate(
                for: itemId,
                with: pending.data
              )
        else { return false }

        gameModel.markMapContentUpdateApplied(
            itemId: itemId,
            counter: pending.counter,
            contentVersion: pending.data.contentVersion
        )
        return true
    }

    func applyPendingMapState(itemId: UUID) async -> Bool {
        guard let pending = gameModel.pendingMapState(for: itemId) else { return false }
        guard gameModel.shouldApplyMapState(itemId: itemId, counter: pending.counter) else {
            gameModel.discardPendingMapState(itemId: itemId)
            return false
        }
        guard await root.mapRoot.gameControllable.hasItem(id: itemId, version: 0),
              await hasMatchingMapAsset(pending.data),
              gameModel.hasMapContentVersion(
                itemId: itemId,
                contentVersion: pending.data.contentVersion
              )
        else { return false }

        guard root.mapRoot.mapGameControllable.updateMap(
            for: itemId,
            with: pending.data
        ) else {
            gameModel.discardPendingMapState(itemId: itemId)
            return false
        }
        gameModel.markMapStateApplied(itemId: itemId, counter: pending.counter)
        return true
    }

    func hasMatchingMapAsset(_ data: NetworkCodableDataType) async -> Bool {
        guard let expectedAssetVersion = data.assetVersion else { return true }
        return await root.mapRoot.mapGameControllable.mapAssetVersion(for: data.id) == expectedAssetVersion
    }

    func recordImportedFullMapGeneration(_ model: GameNetworkModel) async {
        root.mapRoot.mapGameControllable.recordAuthoritativeMapGeneration(
            model.data
        )
        gameModel.recordFullMapContentVersion(
            itemId: model.data.id,
            contentVersion: model.data.contentVersion,
            counter: model.counter
        )
    }

    func completeMapRepairIfSatisfied(itemId: UUID) async -> Bool? {
        guard let requirement = gameModel.pendingMapRepairRequirement(itemId: itemId) else {
            return nil
        }
        if let expectedAssetVersion = requirement.assetVersion,
           await root.mapRoot.mapGameControllable.mapAssetVersion(for: itemId) != expectedAssetVersion {
            return nil
        }
        guard gameModel.hasMapContentVersion(
            itemId: itemId,
            contentVersion: requirement.contentVersion
        ), await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: itemId) else {
            return nil
        }
        return gameModel.completeMapRepair(itemId: itemId)
    }

    func requestFullMap(
        for model: GameNetworkModel,
        requestType: RPGMessageType,
        action: RPGMessageActionType,
        presentsMap: Bool,
        backgroundRetry: Bool = false
    ) async -> GameNetworkModel? {
        let shouldRequest = if backgroundRetry {
            gameModel.beginMapBackgroundRepair(
                itemId: model.data.id,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion,
                presentsMap: presentsMap,
                counter: model.counter
            )
        } else {
            gameModel.beginMapRepair(
                itemId: model.data.id,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion,
                presentsMap: presentsMap,
                counter: model.counter
            )
        }
        guard shouldRequest else { return nil }
        armMapRepairWatchdog(
            itemId: model.data.id,
            version: model.data.version,
            assetVersion: model.data.assetVersion,
            contentVersion: model.data.contentVersion
        )

        return root.gameModel.outgoingMessage(
            replyToMessageID: model.messageID,
            counter: model.counter,
            proxyCounter: model.proxyCounter,
            type: requestType,
            subType: action,
            asMaster: false,
            purpose: .assetRequest,
            data: NetworkCodableDataType(
                id: model.data.id,
                type: .map,
                version: model.data.version,
                data: nil,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion
            )
        )
    }

    func requestMapContent(
        for model: GameNetworkModel,
        presentsMap: Bool
    ) async -> GameNetworkModel? {
        guard gameModel.beginMapRepair(
            itemId: model.data.id,
            assetVersion: model.data.assetVersion,
            contentVersion: model.data.contentVersion,
            presentsMap: presentsMap,
            counter: model.counter
        ) else { return nil }
        armMapRepairWatchdog(
            itemId: model.data.id,
            version: model.data.version,
            assetVersion: model.data.assetVersion,
            contentVersion: model.data.contentVersion
        )

        return root.gameModel.outgoingMessage(
            replyToMessageID: model.messageID,
            counter: model.counter,
            proxyCounter: model.proxyCounter,
            type: .update,
            subType: .generic,
            asMaster: false,
            purpose: .assetRequest,
            data: NetworkCodableDataType(
                id: model.data.id,
                type: .map,
                version: model.data.version,
                data: nil,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion
            )
        )
    }

    /// Re-requests a map repair the master answered with `.failed`, after a growing delay
    /// (2, 4, 8 s) and at most `maximumMapRepairRetries` times per generation. The master
    /// refuses when a player already has two deferred repairs, so a player joining with three
    /// or more broken maps got some of them only after waiting. See CODE_AUDIT_19 §5.6.
    func scheduleMapRepairRetry(itemId: UUID, version: Int) {
        guard let retry = gameModel.failMapRepair(itemId: itemId) else { return }
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1 << retry.attempt))
            guard let self, !Task.isCancelled, self.gameModel.isMapRepairPending(retry) else { return }
            await self.send(
                type: .reveal,
                subType: .mapState,
                updated: NetworkCodableDataType(
                    id: itemId,
                    type: .map,
                    version: version,
                    data: nil,
                    assetVersion: retry.assetVersion,
                    contentVersion: retry.contentVersion
                ),
                relayToProxyClients: false,
                purpose: .assetRequest
            )
            self.armMapRepairWatchdog(
                itemId: itemId,
                version: version,
                assetVersion: retry.assetVersion,
                contentVersion: retry.contentVersion
            )
        }
        gameModel.setMapRepairRetryTask(task, itemId: itemId)
    }

    /// How long a repair request may stay unanswered before it is treated like a `.failed` answer.
    static let mapRepairAnswerTimeout: Duration = .seconds(15)

    /// A repair request can get no answer at all: the game master deliberately ignores a first
    /// request while its own SharePlay publication is still arriving (`SharePlayMapRecoveryTracker`),
    /// and a reply can be lost on the way. `beginMapRepair` coalesces an identical pending repair,
    /// so without this nothing ever asked again, and a player whose Journal copy was late or
    /// unusable never got the map. The silence is handled as a failure, which re-requests with
    /// the bounded backoff of `scheduleMapRepairRetry`. Completing or superseding the repair
    /// cancels this task.
    func armMapRepairWatchdog(
        itemId: UUID,
        version: Int,
        assetVersion: Int?,
        contentVersion: Int?
    ) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: Self.mapRepairAnswerTimeout)
            guard let self, !Task.isCancelled,
                  self.gameModel.isMapRepairPending(
                    PlayerControllerModel.MapRepairRetry(
                        itemId: itemId,
                        assetVersion: assetVersion,
                        contentVersion: contentVersion,
                        attempt: 0
                    )
                  )
            else { return }
            Logger.networking.debug("PlayerController: map repair for \(itemId, privacy: .public) unanswered, requesting again")
            self.scheduleMapRepairRetry(itemId: itemId, version: version)
        }
        gameModel.setMapRepairRetryTask(task, itemId: itemId)
    }

    /// Requests pin photos absent from both the photo game state and persistent
    /// item controller. The map background is delivered with the full map.
    /// Each photo is requested once per connection; SharePlay turns the first
    /// full answer into one group store so peers do not transfer it again.
    func requestMissingMapImages(itemId: UUID) async {
        let missingImages = await root.mapRoot.mapGameControllable.missingMapImages(itemId: itemId)
        for idType in missingImages {
            let isFirstRequest = gameModel.insertRequestedRepairId(idType.id)
            guard isFirstRequest else { continue }
            await send(
                type: .store,
                subType: .store,
                updated: idType,
                relayToProxyClients: false,
                purpose: .assetRequest
            )
        }
    }
}
