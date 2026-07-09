// @copyright André Trettin

import CoreRPG
import Foundation

struct GameNetworkModel: Codable, Sendable {
    var version: Int = 1
    var counter: Int
    var proxyCounter: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var gameConfig: GameConfigModel
    var gameRoster: GameRosterModel = .empty
    var gameControl: GameControlModel = .empty
    var data: NetworkCodableDataType

    init(
        version: Int = 1,
        counter: Int,
        proxyCounter: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        gameConfig: GameConfigModel,
        gameRoster: GameRosterModel = .empty,
        gameControl: GameControlModel = .empty,
        data: NetworkCodableDataType
    ) {
        self.version = version
        self.counter = counter
        self.proxyCounter = proxyCounter
        self.type = type
        self.subType = subType
        self.gameConfig = gameConfig
        self.gameRoster = gameRoster
        self.gameControl = gameControl
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case version
        case counter
        case proxyCounter
        case type
        case subType
        case gameConfig
        case gameRoster
        case gameControl
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        counter = try container.decode(Int.self, forKey: .counter)
        proxyCounter = try container.decode(Int.self, forKey: .proxyCounter)
        type = try container.decode(RPGMessageType.self, forKey: .type)
        subType = try container.decode(RPGMessageActionType.self, forKey: .subType)
        gameConfig = try container.decode(GameConfigModel.self, forKey: .gameConfig)
        gameRoster = try container.decodeIfPresent(GameRosterModel.self, forKey: .gameRoster) ?? .empty
        gameControl = try container.decodeIfPresent(GameControlModel.self, forKey: .gameControl)
            ?? container.decodeIfPresent(LegacyGameControlModel.self, forKey: .gameRoster)?.gameControl
            ?? .empty
        data = try container.decode(NetworkCodableDataType.self, forKey: .data)
    }
}

private struct LegacyGameControlModel: Decodable {
    var controls: [SharingControlModel] = []
    var features: GameFeatureModel = GameFeatureModel()

    var gameControl: GameControlModel {
        GameControlModel(controls: controls, features: features)
    }

    enum CodingKeys: String, CodingKey {
        case controls
        case features
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        controls = try container.decodeIfPresent([SharingControlModel].self, forKey: .controls) ?? []
        features = try container.decodeIfPresent(GameFeatureModel.self, forKey: .features) ?? GameFeatureModel()
    }
}

enum GameMessageOrigin: Hashable, Sendable {
    case direct(ConnectionController.ID?)
    case proxy
    case sharePlay(UUID)
    case file
    case local

    var connectionId: ConnectionController.ID? {
        guard case let .direct(connectionId) = self else { return nil }
        return connectionId
    }

    var isProxy: Bool {
        guard case .proxy = self else { return false }
        return true
    }
}

struct GameMessageKey: Hashable, Sendable {
    let senderId: UUID
    let counter: Int
    let proxyCounter: Int
    let type: RPGMessageType
    let subType: RPGMessageActionType
    let dataId: UUID
    let dataType: NetworkModules
    let dataVersion: Int

    init(model: GameNetworkModel) {
        senderId = model.gameConfig.id
        counter = model.counter
        proxyCounter = model.proxyCounter
        type = model.type
        subType = model.subType
        dataId = model.data.id
        dataType = model.data.type
        dataVersion = model.data.version
    }
}

struct GameMessageEvent: Sendable {
    let model: GameNetworkModel
    let origin: GameMessageOrigin

    var connectionId: ConnectionController.ID? {
        origin.connectionId
    }

    var fromProxy: Bool {
        origin.isProxy
    }

    var deduplicationKey: GameMessageKey? {
        guard model.counter > 0,
              model.subType != .ok,
              model.subType != .failed
        else { return nil }
        return GameMessageKey(model: model)
    }
}

actor GameMessagePipeline {
    private let recentLimit: Int
    private var messages: [GameMessageEvent] = []
    private var processing = false
    private var isCancelled = false
    private var recentKeys: [GameMessageKey] = []
    private var recentKeySet: Set<GameMessageKey> = []

    init(recentLimit: Int = 256) {
        self.recentLimit = recentLimit
    }

    func enqueue(_ event: GameMessageEvent) -> Bool {
        guard !isCancelled else { return false }
        if let key = event.deduplicationKey {
            guard !recentKeySet.contains(key) else { return false }
            remember(key)
        }
        messages.append(event)
        return true
    }

    func next() -> GameMessageEvent? {
        guard !isCancelled, !processing, !messages.isEmpty else { return nil }
        processing = true
        return messages.removeFirst()
    }

    func processed() {
        processing = false
    }

    func cancelAll() {
        messages.removeAll()
        processing = false
        isCancelled = true
        recentKeys.removeAll()
        recentKeySet.removeAll()
    }

    func reset() {
        messages.removeAll()
        processing = false
        isCancelled = false
        recentKeys.removeAll()
        recentKeySet.removeAll()
    }

    private func remember(_ key: GameMessageKey) {
        recentKeys.append(key)
        recentKeySet.insert(key)

        while recentKeys.count > recentLimit {
            let removed = recentKeys.removeFirst()
            recentKeySet.remove(removed)
        }
    }
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
