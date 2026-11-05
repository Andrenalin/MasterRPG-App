// @copyright André Trettin

import CoreRPG
import Foundation

// The weather the game master shows also covers the 3D game table, as rain or snow, clouds,
// stars and lightning without its photo. It stays until the game master shows another weather,
// clears it from the table, or the game ends.

/// The game master's weather on the 3D table: the payload of `.update/.tableWeather`.
struct TableWeatherPresentation: Codable, Sendable, Equatable, MessageMapper {
    /// The weather shown, or the one just cleared.
    let weatherId: UUID
    /// `false` clears the table's weather.
    var isShown: Bool
    /// Orders the game master's changes. Only a newer one applies.
    var sequence: Int
    /// The game the sequence belongs to: a restarted game counts from one again.
    let sessionId: UUID

    /// The `.tableWeather` message's data.
    var networkData: NetworkCodableDataType {
        NetworkCodableDataType(id: weatherId, type: .weather, version: 0, data: encodeData())
    }
}

/// What a device draws on its 3D table: the game master's last table weather, once this device
/// holds that weather. The game master names it before its reveal arrives.
struct TableWeatherState: Equatable, Sendable {
    private struct MasterOrder: Equatable, Sendable {
        let sessionId: UUID
        let sequence: Int
    }

    /// The game master's last applied change, `nil` before the first.
    private(set) var presentation: TableWeatherPresentation?
    /// The weather the table draws: the shown one, as soon as this device holds it.
    private(set) var visibleWeatherId: UUID?
    private var lastMaster: MasterOrder?

    /// The weather the game master shows on the table, also while it is still on its way.
    var shownWeatherId: UUID? {
        guard let presentation, presentation.isShown else { return nil }
        return presentation.weatherId
    }

    /// Applies a change from the game master. Returns `false` for one that is not newer than the
    /// last applied, such as a replay or a late copy.
    /// - Parameter isHeld: whether this device already holds the weather.
    @discardableResult
    mutating func applyMaster(_ newPresentation: TableWeatherPresentation, isHeld: Bool) -> Bool {
        if let lastMaster,
           lastMaster.sessionId == newPresentation.sessionId,
           newPresentation.sequence <= lastMaster.sequence {
            return false
        }
        lastMaster = MasterOrder(sessionId: newPresentation.sessionId, sequence: newPresentation.sequence)
        presentation = newPresentation
        visibleWeatherId = newPresentation.isShown && isHeld ? newPresentation.weatherId : nil
        return true
    }

    /// A weather arrived on this device: the table draws it if it is the one shown.
    mutating func weatherArrived(_ weatherId: UUID) {
        guard shownWeatherId == weatherId else { return }
        visibleWeatherId = weatherId
    }

    /// Forgets everything: a lost connection or the end of the game.
    mutating func reset() {
        presentation = nil
        visibleWeatherId = nil
        lastMaster = nil
    }
}
