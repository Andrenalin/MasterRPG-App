// @copyright André Trettin

import CoreRPG
import Foundation

/// Sender identity — travels with every message. Players send only this;
/// receivers never derive the sender from a roster lookup again.
struct GameSenderModel: Equatable, Codable, Sendable {
    var id: UUID
    var role: GameType
    var name: String
    var characterId: UUID?

    var isMaster: Bool { role == .master }

    var playerModel: PlayerGameModel {
        PlayerGameModel(id: id, type: role, name: name, characterId: characterId)
    }
}

/// The master-authoritative block. Only master messages carry it — a player
/// message structurally cannot change roster, controls, or features.
struct GameMasterStateModel: Equatable, Codable, Sendable {
    var state: GameState
    var adventureId: UUID?
    var adventureTitle: String?
    var players: [PlayerGameModel] = []
    var controls: [SharingControlModel] = []
    var features: GameFeatureModel = GameFeatureModel()
}

struct GameNetworkModel: Codable, Sendable {
    /// Wire format generations:
    /// - 1: shipped 2.6 app — players/controls/features travel inside
    ///      `gameConfig` (`GameNetworkModelV1`).
    /// - 2: explicit `sender` + master-only `masterState` + optional `targetId`.
    ///      Unreleased dev layouts (gameConfig + gameRoster [+ gameControl]) also
    ///      stamped 1 or 2 and are decoded via the legacy fallbacks.
    static let currentVersion = 2

    var version: Int = GameNetworkModel.currentVersion
    var counter: Int
    var proxyCounter: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var masterId: UUID
    var sender: GameSenderModel
    /// Present only in master messages.
    var masterState: GameMasterStateModel?
    /// When set, only the addressed participant processes the message —
    /// responses to a data request no longer flip everyone's screen.
    var targetId: UUID?
    var data: NetworkCodableDataType

    init(
        version: Int = GameNetworkModel.currentVersion,
        counter: Int,
        proxyCounter: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        masterId: UUID,
        sender: GameSenderModel,
        masterState: GameMasterStateModel? = nil,
        targetId: UUID? = nil,
        data: NetworkCodableDataType
    ) {
        self.version = version
        self.counter = counter
        self.proxyCounter = proxyCounter
        self.type = type
        self.subType = subType
        self.masterId = masterId
        self.sender = sender
        self.masterState = masterState
        self.targetId = targetId
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case version
        case counter
        case proxyCounter
        case type
        case subType
        case masterId
        case sender
        case masterState
        case targetId
        case data
        // legacy layouts and compatibility superset
        case gameConfig
        case gameRoster
        case gameControl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        counter = try container.decode(Int.self, forKey: .counter)
        proxyCounter = try container.decode(Int.self, forKey: .proxyCounter)
        type = try container.decode(RPGMessageType.self, forKey: .type)
        subType = try container.decode(RPGMessageActionType.self, forKey: .subType)
        targetId = try container.decodeIfPresent(UUID.self, forKey: .targetId)
        data = try container.decode(NetworkCodableDataType.self, forKey: .data)

        if let sender = try container.decodeIfPresent(GameSenderModel.self, forKey: .sender) {
            self.sender = sender
            masterId = try container.decode(UUID.self, forKey: .masterId)
            masterState = try container.decodeIfPresent(GameMasterStateModel.self, forKey: .masterState)
            return
        }

        // Pure V1 envelope (shipped 2.6): no gameRoster/gameControl keys —
        // everything travels inside gameConfig.
        if !container.contains(.gameRoster), !container.contains(.gameControl),
           let v1Config = try? container.decode(GameConfigModelV1.self, forKey: .gameConfig) {
            (masterId, sender, masterState) = Self.identity(
                config: GameConfigModel(id: v1Config.id, state: v1Config.state, master: v1Config.master),
                players: v1Config.players,
                controls: v1Config.controls,
                features: v1Config.features
            )
            return
        }

        // Unreleased dev layouts: slim gameConfig plus gameRoster [+ gameControl].
        let config = try container.decode(GameConfigModel.self, forKey: .gameConfig)
        let roster = try container.decodeIfPresent(GameRosterModel.self, forKey: .gameRoster) ?? .empty
        let control = try container.decodeIfPresent(GameControlModel.self, forKey: .gameControl)
            ?? container.decodeIfPresent(LegacyGameControlModel.self, forKey: .gameRoster)?.gameControl
            ?? .empty
        (masterId, sender, masterState) = Self.identity(
            config: config,
            players: roster.players,
            controls: control.controls,
            features: control.features
        )
    }

    /// Compatibility superset: every peer generation decodes the same bytes.
    /// V1 peers (shipped 2.6) read players/controls/features from inside
    /// `gameConfig` via the down-mapper; the unreleased dev layouts read
    /// `gameConfig` + `gameRoster`/`gameControl`; current peers read
    /// `sender`/`masterState`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(counter, forKey: .counter)
        try container.encode(proxyCounter, forKey: .proxyCounter)
        try container.encode(type, forKey: .type)
        try container.encode(subType, forKey: .subType)
        try container.encode(masterId, forKey: .masterId)
        try container.encode(sender, forKey: .sender)
        try container.encodeIfPresent(masterState, forKey: .masterState)
        try container.encodeIfPresent(targetId, forKey: .targetId)
        let configV1 = v1Model.gameConfig
        try container.encode(configV1, forKey: .gameConfig)
        try container.encode(GameRosterSuperset(players: configV1.players, controls: configV1.controls, features: configV1.features), forKey: .gameRoster)
        try container.encode(GameControlModel(controls: configV1.controls, features: configV1.features), forKey: .gameControl)
        try container.encode(data, forKey: .data)
    }

    /// Derives sender identity and master state from a legacy config + roster.
    private static func identity(
        config: GameConfigModel,
        players: [PlayerGameModel],
        controls: [SharingControlModel],
        features: GameFeatureModel
    ) -> (masterId: UUID, sender: GameSenderModel, masterState: GameMasterStateModel?) {
        if config.isMaster {
            let sender = GameSenderModel(id: config.id, role: .master, name: config.master.name, characterId: nil)
            let state = GameMasterStateModel(
                state: config.state,
                adventureId: config.master.adventureId,
                adventureTitle: config.master.adventureTitle,
                players: players,
                controls: controls,
                features: features
            )
            return (config.master.id, sender, state)
        }
        let player = players.first(where: { $0.id == config.id })
        let sender = GameSenderModel(id: config.id, role: player?.type ?? .notSet, name: player?.name ?? "", characterId: player?.characterId)
        return (config.master.id, sender, nil)
    }
}

extension GameNetworkModel {
    var usesFileJournal: Bool {
        guard type == .reveal || type == .store else { return false }
        return data.usesFileJournal
    }
}

extension NetworkCodableDataType {
    var usesFileJournal: Bool {
        guard data != nil else { return false }
        switch type {
        case .pdf, .audio, .space, .photo:
            return true
        default:
            return false
        }
    }
}

// MARK: - V1 wire format (shipped 2.6 app)

/// The envelope exactly as the first release sends and expects it: roster,
/// sharing controls and feature gates travel inside `gameConfig`. Restored so
/// old and new app versions can play in the same game.
struct GameNetworkModelV1: Codable, Sendable {
    var version: Int = 1
    var counter: Int
    var proxyCounter: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var gameConfig: GameConfigModelV1
    var data: NetworkCodableDataType
}

/// V1 shape of `GameConfigModel` — identity plus the embedded roster/control
/// state that the current envelope splits into `sender`/`masterState`.
struct GameConfigModelV1: Equatable, Codable, Sendable {
    var id: UUID
    var state: GameState
    var master: MasterGameModel
    var players: [PlayerGameModel]
    var controls: [SharingControlModel]
    var features: GameFeatureModel
}

extension GameNetworkModelV1 {
    /// Up-map V1 → V2. Keeps `version` at 1 so receivers can tell the peer is old.
    var v2Model: GameNetworkModel {
        let config = GameConfigModel(id: gameConfig.id, state: gameConfig.state, master: gameConfig.master)
        let identity = GameNetworkModel.legacyIdentity(
            config: config,
            players: gameConfig.players,
            controls: gameConfig.controls,
            features: gameConfig.features
        )
        return GameNetworkModel(
            version: version,
            counter: counter,
            proxyCounter: proxyCounter,
            type: type,
            subType: subType,
            masterId: identity.masterId,
            sender: identity.sender,
            masterState: identity.masterState,
            data: data
        )
    }
}

extension GameNetworkModel {
    /// Down-map V2 → V1: embed the state back into `gameConfig` the way the
    /// shipped 2.6 app expects it. Player messages carry the sender as the only
    /// roster entry so V1 peers can still resolve the sender name.
    var v1Model: GameNetworkModelV1 {
        let master = MasterGameModel(
            id: masterId,
            type: .master,
            name: sender.isMaster ? sender.name : "",
            adventureId: masterState?.adventureId,
            adventureTitle: masterState?.adventureTitle
        )
        let players = masterState?.players ?? (sender.isMaster ? [] : [sender.playerModel])
        return GameNetworkModelV1(
            version: 1,
            counter: counter,
            proxyCounter: proxyCounter,
            type: type,
            subType: subType,
            gameConfig: GameConfigModelV1(
                id: sender.id,
                state: masterState?.state ?? .started,
                master: master,
                players: players,
                controls: masterState?.controls ?? [],
                features: masterState?.features ?? GameFeatureModel()
            ),
            data: data
        )
    }

    static func legacyIdentity(
        config: GameConfigModel,
        players: [PlayerGameModel],
        controls: [SharingControlModel],
        features: GameFeatureModel
    ) -> (masterId: UUID, sender: GameSenderModel, masterState: GameMasterStateModel?) {
        identity(config: config, players: players, controls: controls, features: features)
    }
}

/// Encode-only shape for the `gameRoster` key: the intermediate dev layout
/// required controls/features inside gameRoster, the later dev layout only
/// reads players — the superset satisfies both decoders.
private struct GameRosterSuperset: Encodable {
    var players: [PlayerGameModel]
    var controls: [SharingControlModel]
    var features: GameFeatureModel
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
    /// A metadata-only delivery (failed journal transfer) and the later full
    /// payload share every other field — payload presence keeps the real bytes
    /// from being dropped as a duplicate.
    let hasData: Bool

    init(model: GameNetworkModel) {
        senderId = model.sender.id
        counter = model.counter
        proxyCounter = model.proxyCounter
        type = model.type
        subType = model.subType
        dataId = model.data.id
        dataType = model.data.type
        dataVersion = model.data.version
        hasData = model.data.data != nil
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
        "counter \(counter) type: \(type) - \(subType), game: \(sender.name) data: \(data.id) \(data.type.token)"
    }
}

extension GameNetworkModel {
    var senderType: GameType { sender.role }
    var senderName: String { sender.name }
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
