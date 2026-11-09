// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// MARK: - Dispatch

extension PlayerController {
    func handle(
        _ model: GameNetworkModel,
        usesSharePlayPlaybackCoordination: Bool = false
    ) async throws -> GameNetworkModel? {
        switch model.data.type {
        case .none, .game, .rule, .setting, .editor, .generator, .search, .adventure:
            return nil
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
        }
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
    ///
    /// Plain main-actor and synchronous: under approachable concurrency a `nonisolated async`
    /// version ran on its caller and only awaited main-actor state, which cost a hop and
    /// suggested off-main work that never happened (CODE_AUDIT_Game_Shareplay §3.13).
    func response(
        for model: GameNetworkModel,
        isSuccess: Bool,
        requestData: Bool
    ) -> GameNetworkModel {
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
        // compares with its own before it records the item as available (Audio too, see
        // CODE_AUDIT_Audio2 §5.13).
        let keepsVersion = requestData ||
            model.data.type == .audio ||
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
        return root.gameModel.outgoingMessage(
            counter: model.counter,
            proxyCounter: model.proxyCounter,
            type: model.type,
            subType: subType,
            asMaster: false,
            data: payload
        )
    }
}
