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

    /// The transport button: plays or pauses the current item the same way. Without a current
    /// item (or outside a game) the controller toggles whatever it holds.
    func togglePlayback(isGameRunning: Bool, networkActions: NetworkActions?) {
        if let currentId = audioController.model.currentId, isGameRunning {
            networkActions?.game(gameController.requestPlay(id: currentId), .playAudio, nil)
        } else {
            audioController.toggle()
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
