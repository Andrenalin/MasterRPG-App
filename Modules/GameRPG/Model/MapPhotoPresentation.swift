// @copyright André Trettin

import CoreRPG
import Foundation

// A photo shown while a map is on screen opens on the map, in the pin photo popover, pointing at
// the room the game master opened last (or the map's center). From there every viewer can switch
// it to full screen or close it on their own device. Each change the game master makes is sent
// to everyone and wins over what a player or observer chose locally.

/// How a photo shown over a map is presented.
enum MapPhotoMode: Int, Codable, Sendable, CaseIterable {
    /// In a popover on the map, pointing at `MapPhotoPresentation.anchor`.
    case popover
    /// In the full-screen photo viewer above the map.
    case fullScreen
    /// Not shown; the map is in front.
    case closed
}

/// The game master's presentation of a photo over a map: the payload of
/// `.update/.photoPresentation`.
struct MapPhotoPresentation: Codable, Sendable, Equatable, MessageMapper {
    let photoId: UUID
    let mapId: UUID
    /// Where the popover points, in the map's canvas coordinates.
    let anchor: CGPoint
    /// The caption, such as a pin's name. `nil` uses the photo's name.
    var title: String? = nil
    var mode: MapPhotoMode
    /// Orders the game master's changes. Only a newer one applies.
    var sequence: Int
    /// The game the sequence belongs to: a restarted game counts from one again.
    let sessionId: UUID

    /// The same presentation in another mode, as the game master's next change.
    func changed(to mode: MapPhotoMode, sequence: Int) -> MapPhotoPresentation {
        var presentation = self
        presentation.mode = mode
        presentation.sequence = sequence
        return presentation
    }

    /// The `.photoPresentation` message's data.
    var networkData: NetworkCodableDataType {
        NetworkCodableDataType(id: photoId, type: .photo, version: 0, data: encodeData())
    }
}

/// What a device shows of a photo over a map: the presentation (the game master's, or one this
/// device opened on its own from a pin) and the mode this device chose for it.
struct MapPhotoPresentationState: Equatable, Sendable {
    private struct MasterOrder: Equatable, Sendable {
        let sessionId: UUID
        let sequence: Int
    }

    /// The presentation shown, `nil` when no photo is shown over a map.
    private(set) var presentation: MapPhotoPresentation?
    /// Whether this device opened the presentation on its own: a player's full-screen pin photo,
    /// or the game master's of a pin hidden from the players. Its changes are never sent.
    private(set) var isLocal = false
    /// The mode this device shows: the game master's, until the viewer changes it locally.
    private(set) var mode: MapPhotoMode = .closed
    /// Counts every switch to full screen. visionOS opens the photo window on each, also when
    /// the photo is the same as before.
    private(set) var fullScreenRequest = 0
    /// The game master's last applied change. Kept when the photo closes, so a late copy of an
    /// older change does not open it again.
    private var lastMaster: MasterOrder?

    /// Whether a photo is shown over the map, in the popover or full screen.
    var isActive: Bool {
        presentation != nil && mode != .closed
    }

    /// The photo this device shows in the map popover, if any.
    var popover: MapPhotoPresentation? {
        guard mode == .popover else { return nil }
        return presentation
    }

    /// Applies a presentation from the game master. Returns `false` for one that is not newer
    /// than the last applied (a replay or an echo of this device's own change), which leaves the
    /// local choice alone.
    @discardableResult
    mutating func applyMaster(_ newPresentation: MapPhotoPresentation) -> Bool {
        if let lastMaster,
           lastMaster.sessionId == newPresentation.sessionId,
           newPresentation.sequence <= lastMaster.sequence {
            return false
        }
        lastMaster = MasterOrder(sessionId: newPresentation.sessionId, sequence: newPresentation.sequence)
        presentation = newPresentation
        isLocal = false
        setMode(newPresentation.mode)
        return true
    }

    /// A presentation this device opens on its own, such as a pin's photo full screen. The game
    /// master's next change replaces it.
    mutating func presentLocal(_ newPresentation: MapPhotoPresentation) {
        presentation = newPresentation
        isLocal = true
        setMode(newPresentation.mode)
    }

    /// A viewer's own change on this device. Returns whether anything changed.
    @discardableResult
    mutating func setLocal(_ newMode: MapPhotoMode) -> Bool {
        guard presentation != nil, newMode != mode else { return false }
        setMode(newMode)
        return true
    }

    /// The presentation waiting for its photo: the game master's message names the photo before
    /// its reveal arrives.
    func pending(for photoId: UUID) -> MapPhotoPresentation? {
        guard let presentation, presentation.photoId == photoId else { return nil }
        return presentation
    }

    /// Closes the presentation: a photo shown without a map, or another item shown. Keeps the
    /// game master's order.
    mutating func clear() {
        presentation = nil
        isLocal = false
        mode = .closed
    }

    /// Forgets everything: a lost connection or the end of the game.
    mutating func reset() {
        clear()
        lastMaster = nil
    }

    private mutating func setMode(_ newMode: MapPhotoMode) {
        if newMode == .fullScreen {
            fullScreenRequest &+= 1
        }
        mode = newMode
    }
}
