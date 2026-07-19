// @copyright André Trettin

enum GameBattleRoundIndicator: Equatable, Sendable {
    case inactive
    case round(Int)
}

/// Pure presentation policy shared by the game chrome implementations.
/// SharePlay already provides connection state, so a second Wi-Fi indicator
/// would be misleading while a group session is active.
struct GameChromeStatusPresentation: Equatable, Sendable {
    let battleRoundIndicator: GameBattleRoundIndicator
    let showsConnectionStatus: Bool

    init(
        isBattleRunning: Bool,
        battleRound: Int,
        isSharePlayActive: Bool
    ) {
        battleRoundIndicator = isBattleRunning ? .round(battleRound) : .inactive
        showsConnectionStatus = !isSharePlayActive
    }
}
