// @copyright André Trettin

import Foundation

/// What the game remembers about presenting its 3D table, for `GameTablePresentationController`.
/// Used on visionOS, where the table is a window of its own; on iOS and macOS the table replaces
/// the map in place and none of this state is used.
@MainActor @Observable
final class GameTablePresentationModel {
    /// True while the table is being opened, so the automatic open and its retry button cannot
    /// run twice at once.
    var isOpening = false

    /// The game whose start already opened the table by itself: one automatic open per game, so
    /// a table the user closes stays closed when the game screen shows again. Keyed by the game's
    /// id, which is new for every game, instead of being reset at the start of each one.
    @ObservationIgnored var autoOpenedGameId: UUID?

    /// True while the game is being ended, so the seat's Quit, the table window closing and the
    /// game stopping each end it once, and the start window does not open the table again.
    var isEndingGame = false

    /// The table window was closed while the game runs: the start window asks whether to quit.
    var asksToQuit = false
}
