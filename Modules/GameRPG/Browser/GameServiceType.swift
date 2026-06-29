// @copyright André Trettin

import Foundation

enum BrowserConnectionMode: Sendable {
    case observer
    case proxy
}

/// Identifies the Bonjour service role for a given network participant.
///
/// **Naming convention (important):** each case is named from the *advertising* side's
/// perspective — i.e., "what service does this participant expose so that its
/// *counterpart* can find it?"
///
/// | Case | Advertised by | Browsed by | Service string |
/// |------|--------------|------------|----------------|
/// | `.player` | **Master** (initial game) | Player | `_gamemastermaster._tcp` |
/// | `.master` | **Player** (fallback after reconnect) | Master | `_gamemasterplayer._tcp` |
/// | `.proxyServer` | Proxy master | Proxy client | `_gamemasterproxyserver._tcp` |
/// | `.proxyClient` | Proxy client | Proxy master | `_gamemasterproxyclient._tcp` |
///
/// In other words: `.player` is the service string the **master** publishes so that
/// players can discover it; `.master` is the string a **player's fallback listener**
/// publishes so the master can redial after a background disconnect.
enum GameServiceType {
    case player
    case master
    case proxyServer
    case proxyClient

    var serviceName: String {
        switch self {
        case .player:
            return "_gamemastermaster._tcp"
        case .master:
            return "_gamemasterplayer._tcp"
        case .proxyServer:
            return "_gamemasterproxyserver._tcp"
        case .proxyClient:
            return "_gamemasterproxyclient._tcp"
        }
    }

    var connectionMode: BrowserConnectionMode {
        switch self {
        case .player: .observer
        case .master, .proxyServer, .proxyClient: .proxy
        }
    }
}
