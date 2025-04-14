// @copyright André Trettin

import Foundation

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
}
