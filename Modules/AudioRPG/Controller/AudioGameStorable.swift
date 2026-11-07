// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Observation
import os.log

public protocol AudioGameStorable: Sendable {
    // `async throws`, so a failed playlist load or playback start reaches the caller instead of
    // being discarded. See CODE_AUDIT_Game §4.2.
    @MainActor func play(id: UUID, shouldPlay: Bool) async throws
    /// Loads the playlist for `id` and prepares the first item for coordinator sync
    /// without triggering play locally. Used in SharePlay mode where
    /// AVPlayerPlaybackCoordinator propagates play() from the initiating device.
    @MainActor func loadPlaylist(id: UUID) async
    /// `loadPlaylist(id:)` for the play command in `data`: it prepares the track the command
    /// names (not the first one), and does nothing for a pause, which the coordinator
    /// propagates.
    @MainActor func loadPlaylist(with data: NetworkCodableDataType) async

    @MainActor func audioList(allPlayers: Bool, with localDeviceId: UUID) async -> NetworkCodableDataType
    /// Records the game master's version of the item; the reports made for another version no
    /// longer count (the file was replaced during the game). See CODE_AUDIT_Audio2 §5.13.
    @MainActor func setMasterVersion(itemId: UUID, version: Int)
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
    /// Whether `itemId` is a playlist: an item without a file of its own, that only groups the
    /// tracks of its entries. A track is an item with a file.
    @MainActor func isPlaylist(id itemId: UUID) -> Bool
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
