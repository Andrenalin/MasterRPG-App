// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

// MARK: - Show

extension MasterController {
    /// Shows an item to the players. Everyone gets its reference; the players that lack the
    /// item get its package (see `GameNetworkController.sendPresentation`). A player the
    /// reports did not show as lacking it answers with the same counter and is served by
    /// `process(_:)`.
    func show(for idType: NetworkCodableDataType) async {
        // Values are exchanged only as the joining player's Character. There
        // is no general Character/Value presentation protocol during a game.
        guard idType.type != .value else { return }

        if idType.type == .map {
            // Another map (or this one again) is shown: a pin photo shared earlier is over.
            root.mapRoot.mapGameControllable.clearSharedPinPhotos()
        }

        // The files come first: a reveal that reaches this device's own player view (or any
        // player) while the file is still an iCloud placeholder is rejected and only starts the
        // download, so the first tap would do nothing. See `awaitFiles(of:)`.
        await awaitFiles(of: idType)

        let reference: NetworkCodableDataType
        switch idType.type {
        case .map where idType.assetVersion == nil:
            // Call sites of older modules still construct the scale-only reference. The
            // background and content fingerprints are the versions players compare.
            reference = await root.mapRoot.mapGameControllable.shareMap(id: idType.id)
        case .weather:
            // Weather's package identity comes from its linked Photo.
            reference = await root.weatherRoot.weatherGameControllable.shareWeather(id: idType.id)
        default:
            reference = idType.reference
        }
        recordMasterVersion(of: reference)

        if let presentation = newMapPhotoPresentation(for: reference.type, itemId: reference.id) {
            // Before the reveal: a player shows the photo on the map as soon as it arrives.
            await broadcastMapPhoto(presentation)
        }
        if reference.type == .weather {
            // A shown weather also covers the 3D table, once a player holds it.
            await showTableWeather(reference.id)
        }

        let message = outgoingMessage(type: .reveal, subtype: .show, updated: reference)
        gameModel.latestShownCounter = message.counter
        root.statisticsModel.record(message, direction: .outgoing, origin: .direct(nil))
        await store.sendPresentation(
            message,
            missingPlayers: playersMissing(reference),
            isSuperseded: { [gameModel] in gameModel.latestShownCounter != message.counter }
        ) { [self] in
            do {
                return try await createGameData(for: reference)
            } catch {
                Logger.networking.error("MasterController: Cannot create package for \(reference.type.token, privacy: .public) \(reference.id, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }
        if reference.type == .map {
            await sendMapFollowUps(for: reference.id)
        }
        if reference.type == .audio {
            await showAudioStartItems(of: reference.id)
        }
    }

    /// Downloads every iCloud file the shown item needs on the game master's device and waits
    /// for it, so the reveal and its package go out from readable files. A file that never
    /// arrives is logged and the show goes on: the players are then told it is unavailable.
    private func awaitFiles(of idType: NetworkCodableDataType) async {
        let isReady: Bool
        switch idType.type {
        case .audio:
            isReady = await root.audioRoot.audioGameControllable.awaitLocalFileData(for: idType.id)
        case .map:
            isReady = await root.mapRoot.mapGameControllable.awaitMapFiles(itemId: idType.id)
        default:
            guard let access = FileBackedModuleAccess.access(for: idType.type, in: root) else { return }
            isReady = await access.controllable.awaitLocalFileData(for: idType.id)
        }
        if !isReady {
            Logger.networking.error("MasterController: The file of \(idType.type.token, privacy: .public) \(idType.id, privacy: .public) did not download; showing it anyway")
        }
    }

    /// The live part of a map after its reveal: the photo-free content, the state (rooms,
    /// pins, focus) and a running battle round. A paused "Share Map" keeps content and state
    /// private.
    func sendMapFollowUps(
        for mapId: UUID,
        origin: GameMessageOrigin? = nil,
        playerId: UUID? = nil
    ) async {
        let map = root.mapRoot.mapGameControllable
        if mayShareMapState(for: mapId) {
            await send(
                type: .update,
                subtype: .generic,
                updated: map.networkMapContentUpdate(for: mapId),
                origin: origin,
                playerId: playerId,
                authoritativeMaster: true
            )
            await send(
                type: .update,
                subtype: .mapState,
                updated: map.networkMapUpdate(for: mapId),
                origin: origin,
                playerId: playerId,
                authoritativeMaster: true
            )
        }
        if map.battleRoundModel.isRunning, let battleUpdate = map.networkBattleRoundUpdate(for: mapId) {
            await send(
                type: .update,
                subtype: .battleRound,
                updated: battleUpdate,
                origin: origin,
                playerId: playerId,
                authoritativeMaster: true
            )
        }
    }

    /// A map state names the content version it belongs to. When the players last got another
    /// one, the content goes out first: a room the game master just revealed has text the
    /// players did not get while it was hidden.
    func sendMapContentIfChanged(before state: NetworkCodableDataType) async {
        guard let contentVersion = state.contentVersion,
              gameModel.sentMapContentVersions[state.id] != contentVersion
        else { return }
        let content = await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: state.id)
        await send(type: .update, subtype: .generic, updated: content, authoritativeMaster: true)
    }

    /// The master's own version is the baseline every player's report is compared against.
    func recordMasterVersion(of reference: NetworkCodableDataType) {
        let masterId = root.gameModel.gameConfig.id
        let version = reference.effectiveAssetVersion
        FileBackedModuleAccess.access(for: reference.type, in: root)?
            .setMasterVersion(reference.id, version, masterId)
    }

    /// The players whose reports do not show the master's version of the item. Modules without
    /// reports (Map, Weather, Table) name nobody: their players ask.
    func playersMissing(_ reference: NetworkCodableDataType) -> Set<UUID> {
        let masterId = root.gameModel.gameConfig.id
        let players = root.gameModel.gameRoster.players.map(\.id).filter { $0 != masterId }
        if let access = FileBackedModuleAccess.access(for: reference.type, in: root) {
            return Set(players.filter { !access.isAvailable(reference.id, $0, masterId) })
        }
        if reference.type == .audio {
            return Set(root.audioRoot.audioGameControllable.missingPlayers(for: reference.id))
        }
        return []
    }

    /// The package of an item, or `nil` when there is none to send. An iCloud file that has
    /// not downloaded is waited for first, so the package always carries the file; `nil` means
    /// the file never arrived.
    ///
    /// The export requirements are `@concurrent`, so they run off the main actor by
    /// themselves and inherit this task's cancellation. See CODE_AUDIT_18 §7.1 and §4.4.
    func createGameData(for idType: NetworkCodableDataType) async throws -> NetworkCodableDataType? {
        switch idType.type {
        case .map:
            return try await cachedMapPackage(for: idType.id)
        case .audio:
            guard await root.audioRoot.audioGameControllable.awaitLocalFileData(for: idType.id) else { return nil }
            // The same cached, coalesced package as the push and the asset requests: a re-show
            // does not read the file again. See CODE_AUDIT_Game_Photo_Audio §7.5.
            return try await audioPackage(for: idType.id)
        case .weather:
            return try await cachedWeatherPackage(for: idType.id)
        default:
            guard let access = FileBackedModuleAccess.access(for: idType.type, in: root),
                  await access.controllable.awaitLocalFileData(for: idType.id)
            else { return nil }
            return try await cachedPackage(module: idType.type, itemId: idType.id, controllable: access.controllable)
        }
    }
}
