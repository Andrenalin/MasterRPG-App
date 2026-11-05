// @copyright André Trettin

import CoreRPG
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
    /// The player's companions (see `PlayerGameModel.companions`); every message carries the
    /// current list, so the master always has the latest one.
    var companions: [TablePlayerModel] = []

    var isMaster: Bool { role == .master }

    /// Longest a peer-controlled sender name is allowed to be. Clamped once, when a message
    /// is decoded, so every consumer (roster, sharing controls, statistics, participant
    /// names, the pipeline's queue) sees the bounded value. See CODE_AUDIT_17 §6.9 and
    /// CODE_AUDIT_18 §6.3.
    static let maxNameLength = 64

    static func clampedName(_ name: String) -> String {
        name.count > maxNameLength ? String(name.prefix(maxNameLength)) : name
    }

    var playerModel: PlayerGameModel {
        PlayerGameModel(
            id: id,
            type: role,
            name: name,
            characterId: characterId,
            supporterTier: supporterTier,
            companions: companions
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
        case companions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(GameType.self, forKey: .role)
        name = Self.clampedName(try container.decode(String.self, forKey: .name))
        characterId = try container.decodeIfPresent(UUID.self, forKey: .characterId)
        supporterTier = try container.decodeIfPresent(
            SupporterTier.self,
            forKey: .supporterTier
        ) ?? .none
        companions = Array((try container.decodeIfPresent([TablePlayerModel].self, forKey: .companions) ?? [])
            .prefix(PlayerGameModel.maximumCompanions))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(characterId, forKey: .characterId)
        try container.encode(supporterTier, forKey: .supporterTier)
        if !companions.isEmpty {
            try container.encode(companions, forKey: .companions)
        }
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

/// The kind of device a game message was sent from. A player who is not on Vision Pro has no
/// seat at the 3D table; their dice are shown at the table's guest seat instead.
enum GamePlatform: String, Codable, Sendable {
    case iOS
    case macOS
    case tvOS
    case visionOS

    static var current: GamePlatform {
#if os(visionOS)
        .visionOS
#elseif os(tvOS)
        .tvOS
#elseif os(macOS)
        .macOS
#else
        .iOS
#endif
    }
}

struct GameNetworkModel: Codable, Sendable {
    /// The one wire format this app speaks. An envelope stamped with any other version, or one
    /// of an earlier app release that has no `sender` at all, does not decode and is dropped.
    static let currentVersion = 3

    var version: Int = GameNetworkModel.currentVersion
    /// Wall-clock intent time used by last-wins peer events (map pins, Space transforms).
    var timestamp: TimeInterval
    /// The master's message number. A player echoes it in the acknowledgement or the asset
    /// request that answers the message, and the master echoes it again in the delivery.
    var counter: Int
    var proxyCounter: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var masterId: UUID
    var sender: GameSenderModel
    /// Present only in master messages.
    var masterState: GameMasterStateModel?
    /// When set, only the addressed participant processes the message.
    var targetId: UUID?
    /// The device the sender plays on. A player who is not on Vision Pro has no seat at the 3D
    /// table.
    var senderPlatform: GamePlatform?
    var data: NetworkCodableDataType

    init(
        version: Int = GameNetworkModel.currentVersion,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970,
        counter: Int,
        proxyCounter: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        masterId: UUID,
        sender: GameSenderModel,
        masterState: GameMasterStateModel? = nil,
        targetId: UUID? = nil,
        senderPlatform: GamePlatform? = nil,
        data: NetworkCodableDataType
    ) {
        self.version = version
        self.timestamp = timestamp
        self.counter = counter
        self.proxyCounter = proxyCounter
        self.type = type
        self.subType = subType
        self.masterId = masterId
        self.sender = sender
        self.masterState = masterState
        self.targetId = targetId
        self.senderPlatform = senderPlatform
        self.data = data
    }

    /// Thrown from `init(from:)` for an envelope of another wire version.
    struct UnsupportedVersion: LocalizedError {
        let declaredVersion: Int?

        var errorDescription: String? {
            "GameNetworkModel envelope has unsupported version " +
                "\(declaredVersion.map(String.init) ?? "none")"
        }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case timestamp
        case counter
        case proxyCounter
        case type
        case subType
        case masterId
        case sender
        case masterState
        case targetId
        case senderPlatform
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let declaredVersion = try container.decodeIfPresent(Int.self, forKey: .version)
        guard declaredVersion == Self.currentVersion else {
            throw UnsupportedVersion(declaredVersion: declaredVersion)
        }
        version = Self.currentVersion
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        counter = try container.decode(Int.self, forKey: .counter)
        proxyCounter = try container.decode(Int.self, forKey: .proxyCounter)
        type = try container.decode(RPGMessageType.self, forKey: .type)
        subType = try container.decode(RPGMessageActionType.self, forKey: .subType)
        masterId = try container.decode(UUID.self, forKey: .masterId)
        sender = try container.decode(GameSenderModel.self, forKey: .sender)
        masterState = try container.decodeIfPresent(GameMasterStateModel.self, forKey: .masterState)
        targetId = try container.decodeIfPresent(UUID.self, forKey: .targetId)
        // A platform this version does not know is no reason to drop the message.
        senderPlatform = (try? container.decodeIfPresent(String.self, forKey: .senderPlatform))
            .flatMap { $0 }
            .flatMap(GamePlatform.init(rawValue:))
        data = try container.decode(NetworkCodableDataType.self, forKey: .data)
    }
}
