// @copyright André Trettin

enum GameBattleRoundIndicator: Equatable, Sendable {
    case inactive
    case round(Int)
}

enum GameConnectionStatusPresentation: Equatable, Sendable {
    case localNetworkConnected
    case localNetworkLost
    case sharePlayWaiting
    case sharePlayConnected
    case sharePlayLost

    init(lostMaster: Bool, sharePlayState: SharePlayConnectionState) {
        switch sharePlayState {
        case .inactive:
            self = lostMaster ? .localNetworkLost : .localNetworkConnected
        case .waiting:
            self = .sharePlayWaiting
        case .joined:
            self = lostMaster ? .sharePlayLost : .sharePlayConnected
        case .disconnected:
            self = .sharePlayLost
        }
    }
}

/// Pure presentation policy shared by the game chrome implementations.
/// SharePlay already provides connection state, so a second Wi-Fi indicator
/// would be misleading while a group session is active.
struct GameChromeStatusPresentation: Equatable, Sendable {
    let battleRoundIndicator: GameBattleRoundIndicator
    let connectionStatus: GameConnectionStatusPresentation

    init(
        isBattleRunning: Bool,
        battleRound: Int,
        lostMaster: Bool,
        sharePlayState: SharePlayConnectionState
    ) {
        battleRoundIndicator = isBattleRunning ? .round(battleRound) : .inactive
        connectionStatus = GameConnectionStatusPresentation(
            lostMaster: lostMaster,
            sharePlayState: sharePlayState
        )
    }
}
