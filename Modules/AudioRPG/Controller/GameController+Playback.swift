// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Observation
import os.log

/// The audio of a play command could not be loaded, so nothing plays.
struct AudioPlaybackUnavailableError: LocalizedError {
    var errorDescription: String? {
        String(localized: "The audio could not be played. Its file may not be downloaded yet.", bundle: .module)
    }
}

extension GameController: AudioGameStorable {
    @MainActor
    func play(id: UUID, shouldPlay: Bool) async throws {
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
        // A pause that comes in while the playlist loads wins over this play.
        let generation = audioController.model.playbackGeneration
        // A command for a track of the playlist that plays already (resume, next, previous)
        // must not copy every file again. The track may have arrived after the playlist was
        // loaded.
        if let trackId = request.trackId, isLoaded(rootId: id) {
            await syncLoadedPlaylist(id)
            if audioController.model.playList.contains(where: { $0.id == trackId }) {
                await playLoadedTrack(trackId, position: position, generation: generation)
                return
            }
        }
        // A plain play, and the loop, of the playlist that is loaded starts it from its first
        // track in place: the files are copied already. See CODE_AUDIT_Audio2 §7.2.
        if request.trackId == nil, let firstId = list.first?.id, isLoaded(rootId: id) {
            await syncLoadedPlaylist(id)
            if audioController.model.playList.contains(where: { $0.id == firstId }) {
                await audioController.preparePlay(
                    id: firstId,
                    triggerPlay: audioController.model.playbackGeneration == generation,
                    startAt: position,
                    coordinationId: request.coordinationId
                )
                return
            }
        }
        await loadPlaylist(
            id: id,
            list: list,
            trackId: request.trackId,
            triggerPlay: true,
            startAt: position,
            generation: generation,
            coordinationId: request.coordinationId
        )
        // Nothing of the playlist could be loaded (an iCloud file that is offline, a failed copy),
        // and no pause or newer play took over: the caller, an intent among them, must not report
        // that it plays. See CODE_AUDIT_26 §5.100.
        if audioController.model.playListRootId != id, audioController.model.playbackGeneration == generation {
            throw AudioPlaybackUnavailableError()
        }
    }

    /// Replaces the playlist with the one of `id`: only the track to start is copied before it
    /// plays, the others follow in the background (`loadRemainingTracks`), so a long playlist or
    /// an evicted iCloud track does not delay the first note or block the pipeline behind it.
    /// See CODE_AUDIT_Audio2 §7.2.
    @MainActor
    private func loadPlaylist(
        id: UUID,
        list: [AudioModel],
        trackId: UUID?,
        triggerPlay: Bool,
        startAt: TimeInterval?,
        generation: Int,
        coordinationId: UUID? = nil
    ) async {
        guard let firstId = list.first?.id else { return }
        let startId = trackId.flatMap { trackId in list.contains { $0.id == trackId } ? trackId : nil } ?? firstId
        guard let startModel = list.first(where: { $0.id == startId }) else { return }
        // A newer playlist replaced this one while it loaded: its start track is not in the
        // playlist, and selecting it would clear the current item. See CODE_AUDIT_21 §3.4.
        guard await audioController.add(audio: [startModel], replace: true) else { return }
        audioController.model.playListRootId = id
        // `add(replace:)` empties the playlist and the player but keeps `currentItem`. Starting
        // the song that was just stopped found `firstId == currentId`, so `togglePlay` only
        // resumed an empty player and nothing played. Select the new copy explicitly.
        audioController.model.set(currentId: startId)
        loadRemainingTracks(of: id)
        await audioController.preparePlay(
            id: startId,
            triggerPlay: triggerPlay && audioController.model.playbackGeneration == generation,
            startAt: startAt,
            coordinationId: coordinationId
        )
    }

    /// Adds the other tracks of the playlist of `rootId` after the start track, in their place.
    /// A newer replacement of the playlist ends it (the load itself discards its tracks then).
    @MainActor
    private func loadRemainingTracks(of rootId: UUID) {
        let model = audioController.model
        let generation = model.playListGeneration
        model.remainingTracksTask?.cancel()
        model.remainingTracksTask = Task { @MainActor in
            guard !Task.isCancelled, model.playListRootId == rootId, model.playListGeneration == generation else { return }
            await syncLoadedPlaylist(rootId)
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
        await audioController.seekAndWait(to: position)
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

    /// A track arrived. A device that ran out of arrived tracks while the game master's playlist
    /// goes on (the next track came after the current one ended) continues with it. See
    /// CODE_AUDIT_Audio2 §5.7.
    @MainActor
    func itemArrived(id: UUID) async {
        let model = audioController.model
        guard let rootId = model.playListRootId else { return }
        let wasWaitingForTrack = model.isPlaybackComplete && model.isGameRunning()
        let count = model.playList.count
        await syncLoadedPlaylist(rootId)
        guard wasWaitingForTrack, model.isPlaybackComplete, model.playList.count > count,
              let index = model.currentIndex, model.playList.indices.contains(index + 1)
        else { return }
        await audioController.preparePlay(id: model.playList[index + 1].id, triggerPlay: true)
    }

    /// The current track resumes where it is; any other track starts from its beginning.
    @MainActor
    private func playLoadedTrack(_ trackId: UUID, position: TimeInterval?, generation: Int) async {
        let model = audioController.model
        if trackId == model.currentId, !model.isPlaybackComplete, model.currentItem != nil {
            if let position {
                await audioController.seekAndWait(to: position)
            }
            guard model.playbackGeneration == generation else { return }
            audioController.play()
        } else {
            await audioController.preparePlay(
                id: trackId,
                triggerPlay: model.playbackGeneration == generation,
                startAt: position
            )
        }
    }

    @MainActor
    func loadPlaylist(id: UUID) async {
        await loadPlaylist(id: id, trackId: nil)
    }

    @MainActor
    private func loadPlaylist(id: UUID, trackId: UUID?, coordinationId: UUID? = nil) async {
        let list = fetchPlaylist(id: id)
        await loadPlaylist(
            id: id,
            list: list,
            trackId: trackId,
            triggerPlay: false,
            startAt: nil,
            generation: audioController.model.playbackGeneration,
            coordinationId: coordinationId
        )
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
        // A plain play of the playlist that is loaded (the game master's loop, or its restart)
        // prepares the first track in place, as the game master's own device does. Loading the
        // playlist again would empty this device's player, which the coordinated playback
        // passes on to the game master's device as a pause: the replay stopped right after it
        // began.
        if request.trackId == nil, let firstId = fetchPlaylist(id: request.id).first?.id,
           isLoaded(rootId: request.id) {
            await syncLoadedPlaylist(request.id)
            if model.playList.contains(where: { $0.id == firstId }) {
                await audioController.preparePlay(id: firstId, triggerPlay: false, coordinationId: request.coordinationId)
                return
            }
        }
        await loadPlaylist(id: request.id, trackId: request.trackId, coordinationId: request.coordinationId)
    }

    @MainActor
    func audioList(allPlayers: Bool, with localDeviceId: UUID) async -> NetworkCodableDataType {
        let request: AudioListRequest
        if allPlayers {
            var players: [UUID: [UUID]] = [:]
            let itemIds = Set(itemController.itemDataModel.items).union(gameModel.playerReports.keys)
            for itemId in itemIds {
                if await hasLocalDatabaseAudioData(for: itemId) {
                    applyAudio(id: itemId, for: [localDeviceId])
                }
                players[itemId] = gameModel.playerReport(for: itemId)
            }
            request = AudioListRequest(list: [], players: players)
        } else {
            var availableItems: [UUID] = []
            for itemId in itemController.itemDataModel.items {
                guard await hasLocalDatabaseAudioData(for: itemId) else { continue }
                applyAudio(id: itemId, for: [localDeviceId])
                availableItems.append(itemId)
            }
            request = AudioListRequest(list: availableItems, players: [:])
        }
        let data = request.encodeData()
        return NetworkCodableDataType(id: UUID(), type: .audio, version: 0, data: data)
    }
    
    /// Reports the one item `id` for `players`: callers checked that item's own file
    /// (`hasLocalFileData`). A playlist's other tracks are separate items, reported when they
    /// arrive; `allPlayersReported(for:)` asks only for the item and its first track.
    @MainActor
    func setMasterVersion(itemId: UUID, version: Int) {
        gameModel.recordMasterVersion(version, for: itemId)
    }

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
            // A player lists the items it holds, also ones this device does not know yet (it
            // learns who owns an item it may be asked to share). The list is capped so a buggy or
            // modified player cannot grow the report map without bound. See CODE_AUDIT_Audio2 §6.3.
            let reportedItems = Set(list.list.prefix(Self.maximumReportedItems))
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
        // The per-message cap bounds one list, not the sum of many: an item nobody holds and this
        // device does not know leaves no entry behind. See CODE_AUDIT_26 §6.13.
        gameModel.playerReports = Self.prunedReports(
            gameModel.playerReports,
            knownItems: Set(itemController.itemDataModel.items)
        )
        return true
    }

    /// `reports` without the items that no player holds and that are not in `knownItems`.
    static func prunedReports(_ reports: [UUID: [UUID]], knownItems: Set<UUID>) -> [UUID: [UUID]] {
        reports.filter { !$0.value.isEmpty || knownItems.contains($0.key) }
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

    /// The most items one player's availability list may name.
    private static let maximumReportedItems = 5_000

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
