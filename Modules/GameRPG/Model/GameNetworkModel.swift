// @copyright André Trettin

import CoreRPG
import CryptoKit
import Foundation
import os.log

/// Sender identity — travels with every message. Players send only this;
/// receivers never derive the sender from a roster lookup again.
struct GameSenderModel: Equatable, Codable, Sendable {
    var id: UUID
    var role: GameType
    var name: String
    var characterId: UUID?
    var supporterTier: SupporterTier = .none

    var isMaster: Bool { role == .master }

    var playerModel: PlayerGameModel {
        PlayerGameModel(
            id: id,
            type: role,
            name: name,
            characterId: characterId,
            supporterTier: supporterTier
        )
    }
}

extension GameSenderModel {
    enum CodingKeys: String, CodingKey {
        case id
        case role
        case name
        case characterId
        case supporterTier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(GameType.self, forKey: .role)
        name = try container.decode(String.self, forKey: .name)
        characterId = try container.decodeIfPresent(UUID.self, forKey: .characterId)
        supporterTier = try container.decodeIfPresent(
            SupporterTier.self,
            forKey: .supporterTier
        ) ?? .none
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(characterId, forKey: .characterId)
        try container.encode(supporterTier, forKey: .supporterTier)
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

/// The logical recipient set is independent from the physical transport.
/// SharePlay may still deliver a master-only message to the whole session, but
/// peers can reject it before running any module handler and a LAN bridge must
/// never fan it out.
enum GameMessageAudience: Int, Codable, Hashable, Sendable {
    /// Used only when decoding an older envelope that did not carry an audience.
    case automatic = 0
    case master = 1
    case group = 2
    case target = 3
}

/// Separates a user action from a request for missing bytes. Historically both
/// used a data-less reveal/store, which made a proxy host swallow presentations
/// as if they were local cache repairs.
enum GameMessagePurpose: Int, Codable, Hashable, Sendable {
    /// Used only for envelopes produced before `purpose` was introduced.
    case legacy = 0
    case event = 1
    case assetRequest = 2
}

struct GameNetworkModel: Codable, Sendable {
    /// Wire format generations:
    /// - 1: shipped 2.6 app — players/controls/features travel inside
    ///      `gameConfig` (`GameNetworkModelV1`).
    /// - 2: explicit `sender` + master-only `masterState` + optional `targetId`.
    ///      Unreleased dev layouts (gameConfig + gameRoster [+ gameControl]) also
    ///      stamped 1 or 2 and are decoded via the legacy fallbacks.
    /// Current in-memory schema. Encoded messages still advertise the V1 wire
    /// version because the encoder emits a compatibility superset for old peers.
    static let currentVersion = 2

    var version: Int = GameNetworkModel.currentVersion
    /// Stable identity for one logical send. Transport retries and bridge copies
    /// retain this value, allowing admission and delivery receipts to correlate
    /// without relying on independent per-device counters.
    var messageID: UUID?
    /// The master message answered by this acknowledgement or asset request.
    /// Ordinary player events leave it nil.
    var replyToMessageID: UUID?
    /// Wall-clock intent time used only by last-wins peer events. Counter ordering
    /// remains the compatibility fallback for envelopes produced by older peers.
    var timestamp: TimeInterval
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
    var audience: GameMessageAudience
    var purpose: GameMessagePurpose
    /// Control-plane Messenger packet that authenticates a later anonymous
    /// GroupSessionJournal attachment. `nil` is the backwards-compatible wire
    /// value for every real presentation, including attachment-reuse events.
    var journalAdmissionOnly: Bool?
    /// SHA-256 of the raw GroupSessionJournal attachment. The physically
    /// attributed Messenger admission carries this value, binding otherwise
    /// anonymous Journal bytes to the participant that announced them.
    var journalPayloadDigest: Data?
    var data: NetworkCodableDataType

    init(
        version: Int = GameNetworkModel.currentVersion,
        messageID: UUID? = UUID(),
        replyToMessageID: UUID? = nil,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970,
        counter: Int,
        proxyCounter: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        masterId: UUID,
        sender: GameSenderModel,
        masterState: GameMasterStateModel? = nil,
        targetId: UUID? = nil,
        audience: GameMessageAudience = .automatic,
        purpose: GameMessagePurpose = .event,
        journalAdmissionOnly: Bool? = nil,
        journalPayloadDigest: Data? = nil,
        data: NetworkCodableDataType
    ) {
        self.version = version
        self.messageID = messageID
        self.replyToMessageID = replyToMessageID
        self.timestamp = timestamp
        self.counter = counter
        self.proxyCounter = proxyCounter
        self.type = type
        self.subType = subType
        self.masterId = masterId
        self.sender = sender
        self.masterState = masterState
        self.targetId = targetId
        self.audience = audience
        self.purpose = purpose
        self.journalAdmissionOnly = journalAdmissionOnly
        self.journalPayloadDigest = journalPayloadDigest
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case version
        case messageID
        case replyToMessageID
        case timestamp
        case counter
        case proxyCounter
        case type
        case subType
        case masterId
        case sender
        case masterState
        case targetId
        case audience
        case purpose
        case journalAdmissionOnly
        case journalPayloadDigest
        case data
        // legacy layouts and compatibility superset
        case gameConfig
        case gameRoster
        case gameControl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        messageID = try container.decodeIfPresent(UUID.self, forKey: .messageID)
        replyToMessageID = try container.decodeIfPresent(UUID.self, forKey: .replyToMessageID)
        timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp) ?? 0
        counter = try container.decode(Int.self, forKey: .counter)
        proxyCounter = try container.decode(Int.self, forKey: .proxyCounter)
        type = try container.decode(RPGMessageType.self, forKey: .type)
        subType = try container.decode(RPGMessageActionType.self, forKey: .subType)
        targetId = try container.decodeIfPresent(UUID.self, forKey: .targetId)
        audience = try container.decodeIfPresent(GameMessageAudience.self, forKey: .audience) ?? .automatic
        purpose = try container.decodeIfPresent(GameMessagePurpose.self, forKey: .purpose) ?? .legacy
        journalAdmissionOnly = try container.decodeIfPresent(Bool.self, forKey: .journalAdmissionOnly)
        journalPayloadDigest = try container.decodeIfPresent(Data.self, forKey: .journalPayloadDigest)
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
    /// `sender`/`masterState`. The version key stays at V1 so old clients do not
    /// reject an otherwise compatible envelope.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(GameNetworkModelV1.wireVersion, forKey: .version)
        try container.encodeIfPresent(messageID, forKey: .messageID)
        try container.encodeIfPresent(replyToMessageID, forKey: .replyToMessageID)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(counter, forKey: .counter)
        try container.encode(proxyCounter, forKey: .proxyCounter)
        try container.encode(type, forKey: .type)
        try container.encode(subType, forKey: .subType)
        try container.encode(masterId, forKey: .masterId)
        try container.encode(sender, forKey: .sender)
        try container.encodeIfPresent(masterState, forKey: .masterState)
        try container.encodeIfPresent(targetId, forKey: .targetId)
        try container.encode(audience, forKey: .audience)
        try container.encode(purpose, forKey: .purpose)
        try container.encodeIfPresent(journalAdmissionOnly, forKey: .journalAdmissionOnly)
        try container.encodeIfPresent(journalPayloadDigest, forKey: .journalPayloadDigest)
        let configV1 = v1Model.gameConfig
        try container.encode(configV1, forKey: .gameConfig)
        try container.encode(GameRosterSuperset(players: configV1.players, controls: configV1.controls, features: configV1.features), forKey: .gameRoster)
        try container.encode(GameControlModel(controls: configV1.controls, features: configV1.features), forKey: .gameControl)
        try container.encode(data, forKey: .data)
    }

    nonisolated static func journalDigest(for payload: Data) -> Data {
        Data(SHA256.hash(data: payload))
    }

    var resolvedJournalPayloadDigest: Data? {
        if let payload = data.data {
            return Self.journalDigest(for: payload)
        }
        return journalPayloadDigest
    }

    /// Compares the immutable control-plane identity while binding a full
    /// callback to the digest recomputed from its loaded bytes. Admission-only
    /// is deliberately excluded because the Messenger half is marked and the
    /// real Journal metadata is not.
    func hasSameJournalFingerprint(as other: GameNetworkModel) -> Bool {
        version == other.version &&
            replyToMessageID == other.replyToMessageID &&
            masterId == other.masterId &&
            sender == other.sender &&
            masterState == other.masterState &&
            counter == other.counter &&
            proxyCounter == other.proxyCounter &&
            type == other.type &&
            subType == other.subType &&
            audience == other.audience &&
            purpose == other.purpose &&
            targetId == other.targetId &&
            data.id == other.data.id &&
            data.type == other.data.type &&
            data.version == other.data.version &&
            data.assetVersion == other.data.assetVersion &&
            data.contentVersion == other.data.contentVersion &&
            timestamp == other.timestamp &&
            resolvedJournalPayloadDigest == other.resolvedJournalPayloadDigest
    }

    /// Derives sender identity and master state from a legacy config + roster.
    /// Widened from `private` to file-default (internal) so
    /// `GameNetworkModel.legacyIdentity(...)` in GameNetworkModelV1.swift —
    /// split into its own file — can still reach it. See CODE_AUDIT §9.10.
    static func identity(
        config: GameConfigModel,
        players: [PlayerGameModel],
        controls: [SharingControlModel],
        features: GameFeatureModel
    ) -> (masterId: UUID, sender: GameSenderModel, masterState: GameMasterStateModel?) {
        if config.isMaster {
            let sender = GameSenderModel(
                id: config.id,
                role: .master,
                name: config.master.name,
                characterId: nil,
                supporterTier: config.master.supporterTier
            )
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
        let role: GameType = if let type = player?.type, type != .notSet {
            type
        } else {
            .player
        }
        let name = if let playerName = player?.name, !playerName.isEmpty {
            playerName
        } else {
            "Player \(config.id.uuidString.prefix(8))"
        }
        let sender = GameSenderModel(
            id: config.id,
            role: role,
            name: name,
            characterId: player?.characterId,
            supporterTier: player?.supporterTier ?? .none
        )
        return (config.master.id, sender, nil)
    }
}

// The routing-policy extension, V1 wire-compat shim, and message pipeline
// actor now live in their own files — see CODE_AUDIT §9.10.
