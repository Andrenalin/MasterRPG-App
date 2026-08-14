// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import os.log
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import PdfRPG
import SpaceRPG

// MARK: - Dispatch

extension PlayerController {
    func handle(
        _ model: GameNetworkModel,
        usesSharePlayPlaybackCoordination: Bool = false,
        locallyMirroredProxyPresentation: Bool = false
    ) async throws -> GameNetworkModel? {
        switch model.data.type {
        case .none, .game, .rule, .setting, .editor, .search:
            return nil
        case .generator:
            return await handleGeneratedValue(model)
        case .adventure:
            return handleAdventure(model)
        case .audio:
            return try await handleAudio(
                model,
                usesSharePlayPlaybackCoordination: usesSharePlayPlaybackCoordination
            )
        case .dice:
            return try await handleDice(model)
        case .pdf:
            return try await handlePdf(
                model,
                locallyMirroredProxyPresentation: locallyMirroredProxyPresentation
            )
        case .photo:
            return try await handlePhoto(
                model,
                locallyMirroredProxyPresentation: locallyMirroredProxyPresentation
            )
        case .map:
            return try await handleMap(model)
        case .table:
            return try await handleTable(model)
        case .weather:
            return try await handleWeather(model)
        case .value:
            return try await handleValue(model)
        case .space:
            return try await handleSpace(
                model,
                locallyMirroredProxyPresentation: locallyMirroredProxyPresentation
            )
        @unknown default:
            Logger.networking.error("PlayerController: Received unsupported module \(model.data.type.token, privacy: .public); ignoring.")
            return nil
        }
    }

    func handleAdventure(_ model: GameNetworkModel) -> GameNetworkModel? {
        nil
    }

    @MainActor
    func handleGeneratedValue(_ model: GameNetworkModel) -> GameNetworkModel? {
        guard model.sender.isMaster,
              model.type == .update,
              model.subType == .generatedValue,
              let summary = ItemGenerationSummary.decodeData(of: model.data.data)
        else {
            return nil
        }
        root.gameModel.receivedGenerationSummary = summary
        return nil
    }

    /// Shared by every module's `retryDeferredXReveals`: whether a deferred reveal still
    /// matches the master's latest presentation intent before applying it late.
    func deferredPresentationIsCurrent(_ model: GameNetworkModel) async -> Bool {
        await gameModel.shouldProcessPresentation(
            from: model.masterId,
            senderID: model.sender.id,
            module: model.data.type,
            itemId: model.data.id,
            version: model.data.version,
            counter: model.counter,
            timestamp: model.timestamp,
            isRepair: false
        )
    }
}

// MARK: - Response building

extension PlayerController {
    nonisolated func response(
        for model: GameNetworkModel,
        isSuccess: Bool,
        requestData: Bool,
        requestedVersion: Int? = nil
    ) async -> GameNetworkModel {
        let subType: RPGMessageActionType = requestData ? model.subType : (isSuccess ? .ok : .failed)
        // A "please send more" request only needs to name the item: the master
        // rebuilds the payload from `data.id` via createGameData and never reads
        // these bytes. Echoing `model.data` verbatim used to re-upload whatever
        // we just received — e.g. a map that's merely short its background photo
        // sent its whole multi-MB self straight back upstream over the slow,
        // small-message-oriented player→master path, for nothing.
        let preservesAssetVersion = model.data.type == .photo ||
            model.data.type == .pdf ||
            model.data.type == .space ||
            model.data.type == .map ||
            model.data.type == .table ||
            model.data.type == .weather
        let version = if requestData {
            requestedVersion ?? model.data.version
        } else if preservesAssetVersion {
            model.data.version
        } else {
            0
        }
        let payload = NetworkCodableDataType(
            id: model.data.id,
            type: model.data.type,
            version: version,
            data: nil,
            assetVersion: preservesAssetVersion && requestedVersion == nil ? model.data.assetVersion : nil,
            contentVersion: preservesAssetVersion ? model.data.contentVersion : nil
        )
        // Echo the counter of the message being answered (same precedent as the
        // mapState re-request below) instead of minting a fresh one. The pipeline
        // already deduplicates the incoming trigger, so this stays exactly-once;
        // it also lets the master's message log match the ack back to the row it
        // created for the original send — with a fresh counter here that link
        // was counter-space garbage and the log's delivery indicator could never
        // leave "missing players", on every transport, not just file sharing.
        return await root.gameModel.outgoingMessage(
            replyToMessageID: model.messageID,
            counter: model.counter,
            proxyCounter: model.proxyCounter,
            type: model.type,
            subType: subType,
            asMaster: false,
            purpose: requestData ? .assetRequest : .event,
            data: payload
        )
    }
}
