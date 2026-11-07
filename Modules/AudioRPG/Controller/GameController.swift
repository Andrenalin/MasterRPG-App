// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Observation
import os.log

public protocol AudioGameStorable: Sendable {
    // Returning a Task<Void, Error> instead of being async throws let both
    // call sites discard `.result` (and any thrown error) via `let _ =`.
    // See CODE_AUDIT_Game §4.2.
    @MainActor func play(id: UUID?, shouldPlay: Bool) async throws
    /// Loads the playlist for `id` and prepares the first item for coordinator sync
    /// without triggering play locally. Used in SharePlay mode where
    /// AVPlayerPlaybackCoordinator propagates play() from the initiating device.
    @MainActor func loadPlaylist(id: UUID) async
    /// `loadPlaylist(id:)` for the play command in `data`: it prepares the track the command
    /// names (not the first one), and does nothing for a pause, which the coordinator
    /// propagates.
    @MainActor func loadPlaylist(with data: NetworkCodableDataType) async

    @MainActor func audioList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType
    @MainActor func applyAudio(id: UUID, for players: [UUID])
    @discardableResult
    @MainActor func applyAudioList(data: NetworkCodableDataType, for playerId: UUID, authoritative: Bool) -> Bool
    /// The players that lack what `itemId` needs to start: the item itself and, for a playlist,
    /// its first track. The other tracks are sent ahead while the one before them plays.
    @MainActor func missingPlayers(for itemId: UUID) -> [UUID]
    /// The players that lack the item `itemId` itself, whatever its playlist holds.
    @MainActor func missingPlayers(ofItem itemId: UUID) -> [UUID]
    /// Whether `playerId` reported what `itemId` needs to start (see `missingPlayers(for:)`).
    @MainActor func isAudioAvailable(itemId: UUID, for playerId: UUID) -> Bool
    /// The items a playlist needs on a device before it can start: the item itself and, for a
    /// playlist, its first track.
    @MainActor func startItemIds(for itemId: UUID) -> [UUID]
    /// The items a play command needs on every device before it starts: the start items of the
    /// playlist, and the track the command names. Empty for a pause.
    @MainActor func requiredItemIds(for data: NetworkCodableDataType) -> [UUID]
    /// The track that follows `trackId` in the playlist of `rootId`, if any.
    @MainActor func nextTrackId(after trackId: UUID, in rootId: UUID) -> UUID?
    /// A package arrived on this device: a track that belongs to the loaded playlist joins it.
    @MainActor func itemArrived(id: UUID) async
    /// Whether the file of the item `itemId` itself is on this device (not its other tracks).
    func hasLocalAudioData(for itemId: UUID) async -> Bool
    @MainActor func play(with data: NetworkCodableDataType) async throws
    func shouldPlay(with data: NetworkCodableDataType) -> Bool
    /// A fresh play command built from the request in `data`, or `nil` when `data` is not a
    /// well-formed, small request for `data.id`. Lets the master pass on what it understood
    /// instead of relaying a peer's payload. See CODE_AUDIT_23 §6.3.
    func sanitizedPlayRequest(from data: NetworkCodableDataType) -> NetworkCodableDataType?
    @MainActor func requestPlay(id: UUID) -> NetworkCodableDataType
    /// Registers what the game master's loop does instead of restarting the playlist on this
    /// device alone: it receives the play command that starts the playlist again for everyone.
    /// `nil` (no game, or the game ended) makes the loop restart locally again.
    @MainActor func setLoopReplayHandler(_ handler: (@MainActor (NetworkCodableDataType) -> Void)?)
    /// Registers what the game master does whenever a track starts on this device: it is told the
    /// playlist item and the track, to send the next track ahead. `nil` removes it.
    @MainActor func setTrackStartHandler(_ handler: (@MainActor (_ rootId: UUID, _ trackId: UUID) -> Void)?)
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, audioController: AudioController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController
        
        self.audioController = audioController
        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
    }

    let itemController: ItemController
    let exportController: ExportController

    let audioController: AudioController
    let gameModel: ItemGameModel

}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    // A playlist is not one unit on the wire. Every track is an item with a file of its own and
    // is sent, reported and acknowledged on its own: a playlist of many files cannot travel as
    // one package (SharePlay uploads one file per Journal slot). A report names the item that
    // was received, never the tracks of its playlist.

    /// The items a playlist needs on a device before it can start: the item itself and its first
    /// track (the same item for a track that is its own playlist's first). Every other track is
    /// sent ahead while the one before it plays.
    @MainActor func startItemIds(for id: UUID) -> [UUID] {
        guard let firstTrackId = fetchPlaylist(id: id).first?.id, firstTrackId != id else { return [id] }
        return [id, firstTrackId]
    }

    @MainActor func allPlayersReported(for id: UUID) -> Bool {
        missingPlayers(for: id).isEmpty
    }

    @MainActor func missingPlayers(for itemId: UUID) -> [UUID] {
        Set(startItemIds(for: itemId).flatMap { missingPlayers(ofItem: $0) }).sorted()
    }

    @MainActor func missingPlayers(ofItem itemId: UUID) -> [UUID] {
        let reported = Set(gameModel.playerReport(for: itemId))
        return Set(gameModel.currentPlayers).subtracting(reported).sorted()
    }

    @MainActor func isAudioAvailable(itemId: UUID, for playerId: UUID) -> Bool {
        startItemIds(for: itemId).allSatisfy { gameModel.playerReport(for: $0).contains(playerId) }
    }

    @MainActor func requiredItemIds(for data: NetworkCodableDataType) -> [UUID] {
        guard let request = AudioPlayRequest.decodeData(of: data.data), request.shouldPlay else { return [] }
        var ids = startItemIds(for: request.id)
        if let trackId = request.trackId,
           !ids.contains(trackId),
           fetchPlaylist(id: request.id).contains(where: { $0.id == trackId }) {
            ids.append(trackId)
        }
        return ids
    }

    @MainActor func nextTrackId(after trackId: UUID, in rootId: UUID) -> UUID? {
        let ids = fetchPlaylist(id: rootId).map(\.id)
        guard let index = ids.firstIndex(of: trackId), ids.indices.contains(index + 1) else { return nil }
        return ids[index + 1]
    }

    /// The players a share of `itemId` lists. A player counts as reported once they have what the
    /// playlist needs to start (see `missingPlayers(for:)`).
    @MainActor func playerReportStatuses(for itemId: UUID, controls: [SharingControlModel]) -> [PlayerReportStatus] {
        let missing = Set(missingPlayers(for: itemId))
        return controls.playerReportStatuses { !missing.contains($0) }
    }

    @MainActor func report(itemId: UUID, for player: UUID) {
        guard !gameModel.playerReport(for: itemId).contains(player) else { return }
        gameModel.setPlayerReport(playerId: player, for: itemId)
    }
}

extension GameController {
    /// Whether the file of the item itself is on this device. The other tracks of a playlist are
    /// separate items with files of their own, received one by one.
    func hasLocalAudioData(for itemId: UUID) async -> Bool {
        await hasLocalFileData(for: itemId)
    }

    @MainActor
    private func hasLocalDatabaseAudioData(for itemId: UUID) async -> Bool {
        guard let item = itemController.itemSync(for: itemId, noGame: true) else { return false }
        guard let fileUrl = item.fileUrl,
              let fileUrlDataController = itemController.fileUrlDataController
        else { return true }
        return await fileUrlDataController.hasDownloadedData(for: fileUrl)
    }

    @MainActor
    func isPlayingPlaylist(id: UUID) -> Bool {
        guard audioController.model.isPlaying else { return false }
        let list = fetchPlaylist(id: id)
        return list.map { $0.id }.contains(audioController.model.currentId)
    }

    @MainActor
    func fetchPlaylist(id: UUID) -> [AudioModel] {
        var seenIds = Set<UUID>()
        return fetchPlaylist(id: id, seenIds: &seenIds)
    }

    @MainActor
    private func fetchPlaylist(id: UUID, seenIds: inout Set<UUID>) -> [AudioModel] {
        guard !seenIds.contains(id) else { return [] }

        var list: [AudioModel] = []
        seenIds.insert(id)
        let item = gameItem(for: id)
        if item.fileUrl != nil {
            list.append(item)
        }
        item.entries.forEach {
            list.append(contentsOf: fetchPlaylist(id: $0.audioId, seenIds: &seenIds))
        }
        return list
    }
}

extension GameController: AudioGameStorable {
    @MainActor
    func play(id: UUID?, shouldPlay: Bool) async throws {
        guard let id else { return }
        try await play(AudioPlayRequest(id: id, shouldPlay: shouldPlay))
    }

    /// Applies a play command on this device: pauses, resumes or skips within the playlist that
    /// is already loaded, or loads the playlist of `request.id` and starts it (at the named
    /// track, else the first).
    @MainActor
    func play(_ request: AudioPlayRequest) async throws {
        let id = request.id
        let list = fetchPlaylist(id: id)
        let position = request.position.flatMap { Self.isValid(position: $0) ? $0 : nil }
        guard request.shouldPlay else {
            audioController.pause()
            if let position {
                await seekPaused(rootId: id, trackId: request.trackId, to: position)
            }
            return
        }
        // A command for a track of the playlist that plays already (resume, next, previous)
        // must not copy every file again; the loop and a plain play still start it afresh. The
        // track may have arrived after the playlist was loaded.
        if let trackId = request.trackId, isLoaded(rootId: id) {
            await syncLoadedPlaylist(id)
            if audioController.model.playList.contains(where: { $0.id == trackId }) {
                await playLoadedTrack(trackId, position: position)
                return
            }
        }
        // A newer playlist replaced this one while it loaded: its first track is not in the
        // playlist, and selecting it would clear the current item. See CODE_AUDIT_21 §3.4.
        guard await audioController.add(audio: list, replace: true) else { return }
        audioController.model.playListRootId = id
        guard let firstId = list.first?.id else { return }
        let startId = request.trackId.flatMap { trackId in list.contains { $0.id == trackId } ? trackId : nil } ?? firstId
        // `add(replace:)` empties the playlist and the player but keeps `currentItem`. Starting
        // the song that was just stopped found `firstId == currentId`, so `togglePlay` only
        // resumed an empty player and nothing played. Select the new copy explicitly.
        audioController.model.set(currentId: startId)
        await audioController.preparePlay(id: startId, triggerPlay: true)
        if let position {
            audioController.skip(to: position)
        }
    }

    /// A seek while paused: this device stays paused at the position, on the named track.
    @MainActor
    private func seekPaused(rootId: UUID, trackId: UUID?, to position: TimeInterval) async {
        let model = audioController.model
        guard isLoaded(rootId: rootId) else { return }
        await syncLoadedPlaylist(rootId)
        guard let trackId = trackId ?? model.currentId,
              model.playList.contains(where: { $0.id == trackId })
        else { return }
        if trackId != model.currentId {
            await audioController.preparePlay(id: trackId, triggerPlay: false)
        }
        audioController.skip(to: position)
    }

    /// Whether the playlist of `rootId` is the one that is loaded here. It may hold only the
    /// tracks that arrived so far (see `syncLoadedPlaylist`).
    @MainActor
    private func isLoaded(rootId: UUID) -> Bool {
        let model = audioController.model
        return model.playListRootId == rootId && !model.playList.isEmpty
    }

    /// A track that arrived after the playlist was loaded joins it, at its place in the playlist.
    /// The game master sends the tracks one after the other, so a device that started with the
    /// first track gets the next ones while it plays.
    @MainActor
    private func syncLoadedPlaylist(_ rootId: UUID) async {
        let list = fetchPlaylist(id: rootId)
        let model = audioController.model
        let loaded = Set(model.playList.map(\.id))
        let arrived = list.filter { !loaded.contains($0.id) }
        guard !arrived.isEmpty, await audioController.add(audio: arrived) else { return }
        let order = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($0.element.id, $0.offset) })
        model.playList.sort { order[$0.id, default: .max] < order[$1.id, default: .max] }
    }

    @MainActor
    func itemArrived(id: UUID) async {
        guard let rootId = audioController.model.playListRootId else { return }
        await syncLoadedPlaylist(rootId)
    }

    /// The current track resumes where it is; any other track starts from its beginning.
    @MainActor
    private func playLoadedTrack(_ trackId: UUID, position: TimeInterval?) async {
        let model = audioController.model
        if trackId == model.currentId, !model.isPlaybackComplete, model.currentItem != nil {
            audioController.play()
        } else {
            await audioController.preparePlay(id: trackId, triggerPlay: true)
        }
        if let position {
            audioController.skip(to: position)
        }
    }

    @MainActor
    func loadPlaylist(id: UUID) async {
        await loadPlaylist(id: id, trackId: nil)
    }

    @MainActor
    private func loadPlaylist(id: UUID, trackId: UUID?) async {
        let list = fetchPlaylist(id: id)
        guard await audioController.add(audio: list, replace: true) else { return }
        audioController.model.playListRootId = id
        let startId = trackId.flatMap { trackId in list.contains { $0.id == trackId } ? trackId : nil } ?? list.first?.id
        if let startId {
            audioController.model.set(currentId: startId)
            await audioController.preparePlay(id: startId, triggerPlay: false)
        }
    }
    
    @MainActor
    func loadPlaylist(with data: NetworkCodableDataType) async {
        guard let request = AudioPlayRequest.decodeData(of: data.data), request.shouldPlay else { return }
        let model = audioController.model
        if let trackId = request.trackId, isLoaded(rootId: request.id) {
            await syncLoadedPlaylist(request.id)
            if model.playList.contains(where: { $0.id == trackId }) {
                // Resume, next, previous: only a different track is prepared.
                if trackId != model.currentId {
                    await audioController.preparePlay(id: trackId, triggerPlay: false)
                }
                return
            }
        }
        await loadPlaylist(id: request.id, trackId: request.trackId)
    }

    @MainActor
    func audioList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType {
        let request: AudioListRequest
        if allPlayers {
            var players: [UUID: [UUID]] = [:]
            let itemIds = Set(itemController.itemDataModel.items).union(gameModel.playerReports.keys)
            for itemId in itemIds {
                if await hasLocalDatabaseAudioData(for: itemId) {
                    applyAudio(id: itemId, for: [masterId])
                }
                players[itemId] = gameModel.playerReport(for: itemId)
            }
            request = AudioListRequest(list: [], players: players)
        } else {
            var availableItems: [UUID] = []
            for itemId in itemController.itemDataModel.items {
                guard await hasLocalDatabaseAudioData(for: itemId) else { continue }
                applyAudio(id: itemId, for: [masterId])
                availableItems.append(itemId)
            }
            request = AudioListRequest(list: availableItems, players: [:])
        }
        let data = request.encodeData()
        return NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: data)
    }
    
    /// Callers checked the whole playlist first (`hasLocalAudioData`), so its tracks are
    /// reported with it — `allPlayersReported(for:)` asks for every track.
    @MainActor
    func applyAudio(id: UUID, for players: [UUID]) {
        players.forEach {
            report(itemId: id, for: $0)
        }
    }

    @MainActor
    @discardableResult
    func applyAudioList(data: NetworkCodableDataType, for playerId: UUID, authoritative: Bool) -> Bool {
        guard let list = AudioListRequest.decodeData(of: data.data) else { return false }
        if authoritative {
            let itemIds = Set(itemController.itemDataModel.items)
                .union(gameModel.playerReports.keys)
                .union(list.players.keys)
            for itemId in itemIds {
                gameModel.playerReports[itemId] = list.players[itemId] ?? []
            }
        } else {
            let reportedItems = Set(list.list)
            let itemIds = Set(itemController.itemDataModel.items)
                .union(gameModel.playerReports.keys)
                .union(reportedItems)
            for itemId in itemIds {
                var players = gameModel.playerReport(for: itemId).filter { $0 != playerId }
                if reportedItems.contains(itemId) {
                    players.append(playerId)
                }
                gameModel.playerReports[itemId] = players
            }
        }
        return true
    }
    
    @MainActor
    func play(with data: NetworkCodableDataType) async throws {
        guard let request = AudioPlayRequest.decodeData(of: data.data) else { return }
        try await play(request)
    }

    func shouldPlay(with data: NetworkCodableDataType) -> Bool {
        AudioPlayRequest.decodeData(of: data.data)?.shouldPlay ?? false
    }

    /// A position is a finite, non-negative number of seconds.
    static func isValid(position: TimeInterval) -> Bool {
        position.isFinite && position >= 0
    }

    /// A play request is a few small fields; anything larger is not one.
    private static let maximumPlayRequestBytes = 1024

    func sanitizedPlayRequest(from data: NetworkCodableDataType) -> NetworkCodableDataType? {
        guard let payload = data.data,
              payload.count <= Self.maximumPlayRequestBytes,
              let request = AudioPlayRequest.decodeData(of: payload),
              request.id == data.id
        else { return nil }
        var passedOn = request
        passedOn.position = request.position.flatMap { Self.isValid(position: $0) ? $0 : nil }
        return passedOn.command
    }

    @MainActor
    func requestPlay(id: UUID) -> NetworkCodableDataType {
        // Use isPlayingPlaylist rather than comparing currentId == id:
        // currentId is the active *track*, but id is the playlist root item,
        // so a direct comparison almost always returns false even when playing.
        AudioPlayRequest(id: id, shouldPlay: !isPlayingPlaylist(id: id)).command
    }

    /// The item of the playlist that plays: what a transport command names, since a playlist item
    /// of several tracks is not itself a track.
    @MainActor
    var playingRootId: UUID? {
        audioController.model.playListRootId ?? audioController.model.currentId
    }

    /// The command that pauses the playlist on every device.
    @MainActor
    func requestPause() -> NetworkCodableDataType? {
        playingRootId.map { AudioPlayRequest(id: $0, shouldPlay: false).command }
    }

    /// The command that plays `trackId` of the current playlist on every device. The track that
    /// is current resumes where it is, any other starts from its beginning.
    @MainActor
    func requestTrack(_ trackId: UUID) -> NetworkCodableDataType? {
        playingRootId.map { AudioPlayRequest(id: $0, shouldPlay: true, trackId: trackId).command }
    }

    /// The command that moves every device to `position` seconds of the current track. The audio
    /// keeps playing, or stays paused, as it does here. `nil` without a current track or for a
    /// position that is not a finite, non-negative time.
    @MainActor
    func requestSeek(to position: TimeInterval) -> NetworkCodableDataType? {
        let model = audioController.model
        guard Self.isValid(position: position), let currentId = model.currentId, let rootId = playingRootId else { return nil }
        return AudioPlayRequest(id: rootId, shouldPlay: model.wantsPlayback, trackId: currentId, position: position).command
    }

    /// The command that plays the track `offset` away from the current one on every device, or
    /// `nil` at the start or end of the playlist.
    @MainActor
    func requestSkip(offsetBy offset: Int) -> NetworkCodableDataType? {
        let model = audioController.model
        guard let index = model.currentIndex else { return nil }
        let target = index + offset
        guard model.playList.indices.contains(target) else { return nil }
        return requestTrack(model.playList[target].id)
    }

    @MainActor
    func setTrackStartHandler(_ handler: (@MainActor (_ rootId: UUID, _ trackId: UUID) -> Void)?) {
        audioController.model.trackStartHandler = handler
    }

    @MainActor
    func setLoopReplayHandler(_ handler: (@MainActor (NetworkCodableDataType) -> Void)?) {
        audioController.model.loopReplayHandler = handler
    }
}

struct AudioPlayRequest: Codable, Sendable, MessageMapper {
    let id: UUID
    let shouldPlay: Bool
    /// The track of the playlist `id` to play, for resume, next and previous. `nil` plays the
    /// playlist from its first track. Absent in older commands, which decode as `nil`.
    var trackId: UUID? = nil
    /// Where in the track every device continues, in seconds, for a seek. With `shouldPlay` it
    /// seeks while the audio plays; with a pause it seeks while it is paused. `nil` leaves the
    /// position alone. Absent in older commands, which decode as `nil`.
    var position: TimeInterval? = nil

    /// The message that asks the game to play (or pause) `id`.
    var command: NetworkCodableDataType {
        NetworkCodableDataType(id: id, type: .audio, version: 0, data: encodeData())
    }
}

struct AudioListRequest: Codable, Sendable, MessageMapper {
    let list: [UUID]
    let players: [UUID: [UUID]]
}
