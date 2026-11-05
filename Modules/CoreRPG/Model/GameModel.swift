// @copyright André Trettin

import Foundation

public enum GameType: Equatable, Codable, Sendable {
    case notSet
    case master
    case player
    case observer
    case proxy
    case demo
}

public struct MasterGameModel: Equatable, Identifiable, Codable, Sendable {
    public init(
        id: UUID,
        type: GameType,
        name: String,
        adventureId: UUID? = nil,
        adventureTitle: String? = nil,
        supporterTier: SupporterTier = .none
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.adventureId = adventureId
        self.adventureTitle = adventureTitle
        self.supporterTier = supporterTier
    }

    public var id: UUID
    public var type: GameType
    public var name: String
    public var adventureId: UUID?
    public var adventureTitle: String?
    public var supporterTier: SupporterTier

    public static let empty = MasterGameModel(id: UUID(), type: .notSet, name: "")
}

public struct PlayerGameModel: Equatable, Identifiable, Codable, Sendable {
    public init(
        id: UUID,
        type: GameType,
        name: String,
        characterId: UUID? = nil,
        supporterTier: SupporterTier = .none,
        companions: [TablePlayerModel] = []
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.characterId = characterId
        self.supporterTier = supporterTier
        self.companions = Array(companions.prefix(Self.maximumCompanions))
    }
    
    public var id: UUID
    public var type: GameType
    public var name: String
    public var characterId: UUID?
    public var supporterTier: SupporterTier
    /// Characters this player brings along: each enabled one gets a player pin of its own, which
    /// the player moves by default. Sent by the player itself, so capped.
    public var companions: [TablePlayerModel]

    /// Most companions a player may bring; a peer's longer list is cut at decoding.
    public static let maximumCompanions = 8

    public static let empty = PlayerGameModel(id: UUID(), type: .notSet, name: "")
}

extension MasterGameModel {
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case adventureId
        case adventureTitle
        case supporterTier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            type: try container.decode(GameType.self, forKey: .type),
            name: try container.decode(String.self, forKey: .name),
            adventureId: try container.decodeIfPresent(UUID.self, forKey: .adventureId),
            adventureTitle: try container.decodeIfPresent(String.self, forKey: .adventureTitle),
            supporterTier: try container.decodeIfPresent(SupporterTier.self, forKey: .supporterTier) ?? .none
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(adventureId, forKey: .adventureId)
        try container.encodeIfPresent(adventureTitle, forKey: .adventureTitle)
        try container.encode(supporterTier, forKey: .supporterTier)
    }
}

extension PlayerGameModel {
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case characterId
        case supporterTier
        case companions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            type: try container.decode(GameType.self, forKey: .type),
            name: try container.decode(String.self, forKey: .name),
            characterId: try container.decodeIfPresent(UUID.self, forKey: .characterId),
            supporterTier: try container.decodeIfPresent(SupporterTier.self, forKey: .supporterTier) ?? .none,
            companions: try container.decodeIfPresent([TablePlayerModel].self, forKey: .companions) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(characterId, forKey: .characterId)
        try container.encode(supporterTier, forKey: .supporterTier)
        // Left out when empty: the roster travels in every master message.
        if !companions.isEmpty {
            try container.encode(companions, forKey: .companions)
        }
    }
}
