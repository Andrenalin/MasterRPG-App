// @copyright André Trettin

import SwiftUI

enum GameBattleRoundIndicator: Equatable, Sendable {
    case inactive
    case round(Int)
}

enum GameConnectionStatusPresentation: Equatable, Sendable {
    case localNetworkConnected
    case localNetworkReconnecting
    case localNetworkLost
    case sharePlayWaiting
    case sharePlayConnected
    case sharePlayLost

    /// `isReconnecting` reflects `PlayerNetworkController`'s own retry state
    /// (its fallback listener is up and actively waiting for the master to
    /// dial back in with the session's already-known passcode) — real,
    /// in-progress recovery that previously rendered identically to a hard,
    /// permanent loss, giving no feedback that anything was happening and
    /// risking a player force-quitting mid-reconnect. See
    /// CODE_AUDIT_Reconnect §8.1. Meaningless while SharePlay is active, since
    /// SharePlay's own state already governs the indicator there.
    init(lostMaster: Bool, sharePlayState: SharePlayConnectionState, isReconnecting: Bool = false) {
        switch sharePlayState {
        case .inactive:
            if !lostMaster {
                self = .localNetworkConnected
            } else {
                self = isReconnecting ? .localNetworkReconnecting : .localNetworkLost
            }
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
        case .localNetworkReconnecting:
            "Reconnecting…"
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
        case .localNetworkReconnecting:
            "wifi.exclamationmark"
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
        case .sharePlayWaiting, .localNetworkReconnecting:
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
        sharePlayState: SharePlayConnectionState,
        isReconnecting: Bool = false
    ) {
        battleRoundIndicator = isBattleRunning ? .round(battleRound) : .inactive
        connectionStatus = GameConnectionStatusPresentation(
            lostMaster: lostMaster,
            sharePlayState: sharePlayState,
            isReconnecting: isReconnecting
        )
    }
}
