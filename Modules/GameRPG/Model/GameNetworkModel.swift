// @copyright André Trettin

import CoreRPG
import Foundation

struct GameNetworkModel: Codable {
    var version: Int = 1
    var counter: Int
    var proxyCounter: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var gameConfig: GameConfigModel
    var gameRoster: GameRosterModel = .empty
    var data: NetworkCodableDataType
}

extension GameNetworkModel: CustomDebugStringConvertible {
    var debugDescription: String {
        "counter \(counter) type: \(type) - \(subType), game: \(gameConfig.name(in: gameRoster)) data: \(data.id) \(data.type.token)"
    }
}

extension GameNetworkModel {
    var senderType: GameType { gameConfig.type(in: gameRoster) }
    var senderName: String { gameConfig.name(in: gameRoster) }
}

extension GameNetworkModel: MessageMapper {
    static func decodeData(of data: Data?) -> GameNetworkModel? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(GameNetworkModel.self, from: data)
        } catch {
            print("**** Error \(error.localizedDescription)")
        }
        return nil
    }

    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }
}
