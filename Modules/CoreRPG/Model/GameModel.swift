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
    public init(id: UUID, type: GameType, name: String, adventureId: UUID? = nil, adventureTitle: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.adventureId = adventureId
        self.adventureTitle = adventureTitle
    }

    public var id: UUID
    public var type: GameType
    public var name: String
    public var adventureId: UUID?
    public var adventureTitle: String?

    public static let empty = MasterGameModel(id: UUID(), type: .notSet, name: "")
}

public struct PlayerGameModel: Equatable, Identifiable, Codable, Sendable {
    public init(id: UUID, type: GameType, name: String, characterId: UUID? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.characterId = characterId
    }
    
    public var id: UUID
    public var type: GameType
    public var name: String
    public var characterId: UUID?

    public static let empty = PlayerGameModel(id: UUID(), type: .notSet, name: "")
}
