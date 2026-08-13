// @copyright André Trettin

import SwiftUI

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

/// Shared presentation used by every connection-status icon, including the
/// merged join-code/wifi button — see `GameJoinCodeRevealButton`.
extension GameConnectionStatusPresentation {
    var title: LocalizedStringKey {
        switch self {
        case .localNetworkConnected, .sharePlayConnected:
            "Connected"
        case .localNetworkLost, .sharePlayLost:
            "Connection Lost"
        case .sharePlayWaiting:
            "Waiting for SharePlay"
        }
    }

    var systemImage: String {
        switch self {
        case .localNetworkConnected:
            "wifi"
        case .localNetworkLost:
            "wifi.slash"
        case .sharePlayWaiting, .sharePlayConnected:
            "shareplay"
        case .sharePlayLost:
            "shareplay.slash"
        }
    }

    var tint: Color {
        switch self {
        case .localNetworkConnected, .sharePlayConnected:
            .teal
        case .sharePlayWaiting:
            .orange
        case .localNetworkLost, .sharePlayLost:
            .red
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
