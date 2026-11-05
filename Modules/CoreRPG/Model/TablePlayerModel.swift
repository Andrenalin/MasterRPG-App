// @copyright André Trettin

import Foundation

/// A Character the game master put at the table as a player: it gets a player pin on every
/// shown map, like a player who joined over the network, without a device of its own. Saved
/// per adventure. Name and photo are always read from the Character itself.
public struct TablePlayerModel: Codable, Sendable, Equatable, Hashable, Identifiable {
    public init(id: UUID = UUID(), characterId: UUID, isEnabled: Bool = true) {
        self.id = id
        self.characterId = characterId
        self.isEnabled = isEnabled
    }

    /// The stable id of the player pin, used as the player id of the pin's synthetic roster entry.
    public var id: UUID
    public var characterId: UUID
    public var isEnabled: Bool
}

/// What a table player currently does in the running game.
public enum TablePlayerStatus: Equatable, Sendable {
    /// Has a player pin on the maps.
    case active
    /// Switched off by the game master.
    case disabled
    /// A connected player plays this Character; the table player waits until that player leaves.
    case claimed(by: String)
    /// The Character no longer exists.
    case missing
}

/// Decides which players get a pin: the connected players plus the game master's table players.
/// Pure, so the decisions are testable without a network or a map.
public enum TablePlayerResolver {
    /// The connected players (observers never get a pin) followed by the enabled table players
    /// whose Character exists and is not played by a connected player.
    /// - Parameter name: The Character's name, or `nil` when the Character no longer exists.
    public static func pinPlayers(
        roster: [PlayerGameModel],
        tablePlayers: [TablePlayerModel],
        name: (UUID) -> String?
    ) -> [PlayerGameModel] {
        let players = roster.filter { $0.type != .observer }
        var usedIds = Set(players.map(\.id))
        var usedCharacterIds = Set(players.compactMap(\.characterId))
        var result = players
        for tablePlayer in tablePlayers where tablePlayer.isEnabled {
            guard !usedIds.contains(tablePlayer.id),
                  !usedCharacterIds.contains(tablePlayer.characterId),
                  let characterName = name(tablePlayer.characterId) else { continue }
            usedIds.insert(tablePlayer.id)
            usedCharacterIds.insert(tablePlayer.characterId)
            result.append(PlayerGameModel(
                id: tablePlayer.id,
                type: .player,
                name: characterName,
                characterId: tablePlayer.characterId
            ))
        }
        return result
    }

    public static func status(
        of tablePlayer: TablePlayerModel,
        roster: [PlayerGameModel],
        characterExists: Bool
    ) -> TablePlayerStatus {
        guard characterExists else { return .missing }
        if let player = roster.first(where: { $0.type != .observer && $0.characterId == tablePlayer.characterId }) {
            return .claimed(by: player.name)
        }
        return tablePlayer.isEnabled ? .active : .disabled
    }

    /// Appends a table player for every Character not in `tablePlayers` yet, keeping the order.
    public static func adding(characterIds: [UUID], to tablePlayers: [TablePlayerModel]) -> [TablePlayerModel] {
        var result = tablePlayers
        var known = Set(tablePlayers.map(\.characterId))
        for characterId in characterIds where known.insert(characterId).inserted {
            result.append(TablePlayerModel(characterId: characterId))
        }
        return result
    }
}
