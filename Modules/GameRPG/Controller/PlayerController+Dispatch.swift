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
        usesSharePlayPlaybackCoordination: Bool = false
    ) async throws -> GameNetworkModel? {
        switch model.data.type {
        case .none, .game, .rule, .setting, .editor, .generator, .search:
            return nil
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
            return try await handlePdf(model)
        case .photo:
            return try await handlePhoto(model)
        case .map:
            return try await handleMap(model)
        case .table:
            return try await handleTable(model)
        case .weather:
            return try await handleWeather(model)
        case .value:
            return try await handleValue(model)
        case .space:
            return try await handleSpace(model)
        @unknown default:
            Logger.networking.error("PlayerController: Received unsupported module \(model.data.type.token, privacy: .public); ignoring.")
            return nil
        }
    }

    func handleAdventure(_ model: GameNetworkModel) -> GameNetworkModel? {
        nil
    }
}

// MARK: - Response building

extension PlayerController {
    /// Answers a master message with its own counter: `.ok` or `.failed`, or, with
    /// `requestData`, the message echoed back without bytes, which asks the master for the
    /// item it named.
    ///
    /// Only a reference is answered with a request. A package that arrived and still left the
    /// item unusable (the master could not read its own file, for example) is answered with
    /// `.failed`: asking again would bring the same bytes, without end.
    nonisolated func response(
        for model: GameNetworkModel,
        isSuccess: Bool,
        requestData: Bool
    ) async -> GameNetworkModel {
        let asksForData = requestData && model.data.data == nil
        let subType: RPGMessageActionType = if asksForData {
            model.subType
        } else {
            isSuccess && !requestData ? .ok : .failed
        }
        let requestData = asksForData
        // Only the item is named: the master builds the package itself. Echoing the
        // received data would send a map that merely lacks its background straight back.
        // The file-backed modules keep the versions they answer for, which the master
        // compares with its own before it records the item as available.
        let keepsVersion = requestData ||
            model.data.type == .photo ||
            model.data.type == .pdf ||
            model.data.type == .space ||
            model.data.type == .map ||
            model.data.type == .table ||
            model.data.type == .weather
        let payload = NetworkCodableDataType(
            id: model.data.id,
            type: model.data.type,
            version: keepsVersion ? model.data.version : 0,
            data: nil,
            assetVersion: keepsVersion ? model.data.assetVersion : nil,
            contentVersion: keepsVersion ? model.data.contentVersion : nil
        )
        return await root.gameModel.outgoingMessage(
            counter: model.counter,
            proxyCounter: model.proxyCounter,
            type: model.type,
            subType: subType,
            asMaster: false,
            data: payload
        )
    }
}
