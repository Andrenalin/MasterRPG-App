// @copyright André Trettin

import CoreRPG
import Foundation

// V1 wire-format compatibility shim — split out of GameNetworkModel.swift.
// See CODE_AUDIT §9.10.

/// The envelope exactly as the first release sends and expects it: roster,
/// sharing controls and feature gates travel inside `gameConfig`. Restored so
/// old and new app versions can play in the same game.
struct GameNetworkModelV1: Codable, Sendable {
    static let wireVersion = 1

    var version: Int = GameNetworkModelV1.wireVersion
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
            messageID: nil,
            timestamp: 0,
            counter: counter,
            proxyCounter: proxyCounter,
            type: type,
            subType: subType,
            masterId: identity.masterId,
            sender: identity.sender,
            masterState: identity.masterState,
            audience: .automatic,
            purpose: .legacy,
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
/// reads players — the superset satisfies both decoders. Widened from
/// `private` to file-default (internal) so `GameNetworkModel`'s own
/// `encode(to:)` — which lives in GameNetworkModel.swift now that this file
/// split out — can still reach it. Not used outside these two files. See
/// CODE_AUDIT §9.10.
struct GameRosterSuperset: Encodable {
    var players: [PlayerGameModel]
    var controls: [SharingControlModel]
    var features: GameFeatureModel
}

/// Same file-split rationale as `GameRosterSuperset` above: used by
/// `GameNetworkModel.init(from:)` in GameNetworkModel.swift.
struct LegacyGameControlModel: Decodable {
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
