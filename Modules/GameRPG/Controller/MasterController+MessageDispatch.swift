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

// MARK: - Message Dispatch

extension MasterController {
    func handle(
        _ model: GameNetworkModel,
        connectionId: ConnectionController.ID? = nil
    ) async throws -> NetworkCodableDataType? {
        try await handle(
            model,
            origin: connectionId.map { GameMessageOrigin.direct($0) }
        )
    }

    /// Not `private` because `MasterController+NetworkStoreDelegate.swift`'s
    /// `process(_:)` also calls this directly, from a different file.
    func handle(
        _ model: GameNetworkModel,
        origin: GameMessageOrigin?
    ) async throws -> NetworkCodableDataType? {
        switch model.data.type {
        case .adventure, .none, .rule, .setting, .editor, .generator, .search:
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("MasterController: Request \(model.type.debugDescription, privacy: .public) but model request data is not supported. \(model.debugDescription, privacy: .private)")
            return nil
        case .audio:
            return try await handleAudio(model)
        case .dice:
            return try await handleDice(model)
        case .game:
            return try await handleGame(model)
        case .map:
            return try await handleMap(model, origin: origin)
        case .pdf:
            return try await handlePdf(model)
        case .photo:
            return try await handlePhoto(model)
        case .table:
            return try await handleTable(model)
        case .value:
            return try await handleValue(model)
        case .weather:
            return try await handleWeather(model)
        case .space:
            return try await handleSpace(model)
        @unknown default:
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("MasterController: Request \(model.type.debugDescription, privacy: .public) has an unrecognized module \(model.data.type.token, privacy: .public); ignoring. \(model.debugDescription, privacy: .private)")
            return nil
        }
    }
}
