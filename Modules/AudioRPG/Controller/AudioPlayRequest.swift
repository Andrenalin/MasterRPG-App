// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Observation
import os.log

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
    /// Names this play for the coordinated playback of a SharePlay session, in place of the
    /// track's id. Only a replay of the track that just ended has one: the group still holds
    /// that track as ended, so a play of the same item identifier would end at once. Absent in
    /// other commands and in older ones, which decode as `nil`.
    var coordinationId: UUID? = nil

    /// The message that asks the game to play (or pause) `id`.
    var command: NetworkCodableDataType {
        NetworkCodableDataType(id: id, type: .audio, version: 0, data: encodeData())
    }
}

struct AudioListRequest: Codable, Sendable, MessageMapper {
    let list: [UUID]
    let players: [UUID: [UUID]]
}
