// @copyright André Trettin

import CoreRPG
import Foundation

/// The playback decisions every audio surface shares (player, play list, menu bar player).
/// In a running game a play is requested from the game, which plays it on every device,
/// this one included; outside a game it plays locally.
extension AudioRootModel {
    /// Plays or pauses the item `id`: asks the game when one runs, else toggles it here.
    func playOrRequest(id: UUID, isGameRunning: Bool, networkActions: NetworkActions?) {
        if isGameRunning {
            networkActions?.game(gameController.requestPlay(id: id), .playAudio, nil)
        } else {
            audioController.togglePlay(id: id)
        }
    }

    /// The transport button. In a game it pauses the playlist on every device while it plays, and
    /// resumes the current track on every device while it is paused. Without a current item (or
    /// outside a game) the controller toggles whatever it holds.
    func togglePlayback(isGameRunning: Bool, networkActions: NetworkActions?) {
        guard isGameRunning, let currentId = audioController.model.currentId else {
            audioController.toggle()
            return
        }
        let command = audioController.model.isPlaying
            ? gameController.requestPause()
            : gameController.requestTrack(currentId)
        if let command {
            networkActions?.game(command, .playAudio, nil)
        }
    }

    /// A remote command (lock screen, AirPods, headphone buttons) while a game runs: it takes the
    /// same path as the player's buttons, so every player plays, pauses or skips with this
    /// device. Returns `false` when no game runs: the controller then acts on this device alone.
    ///
    /// The running game's actions are `runningGameActions` (`nil` while none runs).
    func routeRemoteCommand(_ command: RemoteCommand) -> Bool {
        guard let actions = runningGameActions() else { return false }
        switch command {
        case .pause:
            pause(isGameRunning: true, networkActions: actions)
        case .play:
            // Play is not a toggle: a device that plays already has nothing to resume.
            guard !audioController.model.isPlaying else { return true }
            togglePlayback(isGameRunning: true, networkActions: actions)
        case .nextTrack:
            skip(offsetBy: 1, isGameRunning: true, networkActions: actions)
        case .previousTrack:
            skip(offsetBy: -1, isGameRunning: true, networkActions: actions)
        case .changePlaybackPosition(let position):
            seek(to: position, isGameRunning: true, networkActions: actions)
        }
        return true
    }

    /// Seeks the current track to `position` seconds: in a game on every device, so the players
    /// follow the game master, else here. The audio keeps playing, or stays paused.
    func seek(to position: TimeInterval, isGameRunning: Bool, networkActions: NetworkActions?) {
        guard isGameRunning else {
            audioController.skip(to: position)
            return
        }
        if let command = gameController.requestSeek(to: position) {
            networkActions?.game(command, .playAudio, nil)
        }
    }

    /// Pauses the audio: in a game on every device, else here.
    func pause(isGameRunning: Bool, networkActions: NetworkActions?) {
        guard isGameRunning else {
            audioController.pause()
            return
        }
        if let command = gameController.requestPause() {
            networkActions?.game(command, .playAudio, nil)
        }
    }

    /// Plays the item `id` from its first track, and never pauses it: in a game on every device,
    /// else here. Unlike `playOrRequest` it is not a toggle.
    @MainActor
    func startPlayback(id: UUID, isGameRunning: Bool, networkActions: NetworkActions?) async throws {
        if isGameRunning {
            networkActions?.game(AudioPlayRequest(id: id, shouldPlay: true).command, .playAudio, nil)
        } else {
            try await gameController.play(id: id, shouldPlay: true)
        }
    }

    /// The next (`offset` 1) or previous (-1) track. In a game every device plays that track, so
    /// the players follow the game master; outside a game it plays here. At the start or end of
    /// the playlist nothing happens.
    func skip(offsetBy offset: Int, isGameRunning: Bool, networkActions: NetworkActions?) {
        guard isGameRunning else {
            audioController.skipToCurrentItem(offsetBy: offset)
            return
        }
        if let command = gameController.requestSkip(offsetBy: offset) {
            networkActions?.game(command, .playAudio, nil)
        }
    }

    /// Removes the item from the play list. In a game, removing the playing one first asks the
    /// game to pause it, so the other devices stop with this one.
    func remove(id: UUID, isGameRunning: Bool, networkActions: NetworkActions?) {
        if isGameRunning, audioController.model.isPlaying, audioController.model.currentId == id {
            networkActions?.game(gameController.requestPlay(id: id), .playAudio, nil)
        }
        audioController.removeAudio(id: id)
    }
}
