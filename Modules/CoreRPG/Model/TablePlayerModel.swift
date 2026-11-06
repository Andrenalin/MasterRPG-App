// @copyright André Trettin

import Foundation

/// A Character the game master put at the table as a player, or a companion a player brings
/// along: it gets a player pin on every shown map, like a player who joined over the network,
/// without a device of its own. The game master's are saved per adventure, a player's
/// companions on that player's device. Name and photo are always read from the Character itself.
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
    /// A connected player plays this Character (or brought it along first); this entry waits
    /// until that player leaves.
    case claimed(by: String)
    /// The Character no longer exists.
    case missing
}

/// Decides which players get a pin: the connected players, their companions and the game
/// master's table players. One pin per Character; whoever comes first in that order keeps it.
/// Pure, so the decisions are testable without a network or a map.
public enum TablePlayerResolver {
    /// The connected players (observers never get a pin), then the enabled companions of those
    /// players, then the enabled table players — each only while its Character exists and has
    /// no pin yet.
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
        let candidates = players.filter { $0.type == .player }.flatMap(\.companions) + tablePlayers
        for candidate in candidates where candidate.isEnabled {
            guard !usedIds.contains(candidate.id),
                  !usedCharacterIds.contains(candidate.characterId),
                  let characterName = name(candidate.characterId) else { continue }
            usedIds.insert(candidate.id)
            usedCharacterIds.insert(candidate.characterId)
            result.append(PlayerGameModel(
                id: candidate.id,
                type: .player,
                name: characterName,
                characterId: candidate.characterId
            ))
        }
        return result
    }

    /// The companions of a player the game master accepts. A companion's id becomes the id of its
    /// pin and is chosen by the player's device, so one that is the player's own id, repeats in
    /// the list, or is in `takenIds` (other players, their companions, table players) is
    /// dropped, as is the player's own Character. See CODE_AUDIT_24 §6.3.
    public static func acceptedCompanions(
        _ companions: [TablePlayerModel],
        ownerId: UUID,
        ownCharacterId: UUID?,
        takenIds: Set<UUID>
    ) -> [TablePlayerModel] {
        var seen = takenIds.union([ownerId])
        return companions.filter { companion in
            companion.characterId != ownCharacterId && seen.insert(companion.id).inserted
        }
    }

    /// The owner of every companion pin: companion id → the id of the player who brought it.
    public static func companionOwners(roster: [PlayerGameModel]) -> [UUID: UUID] {
        var owners: [UUID: UUID] = [:]
        for player in roster where player.type == .player {
            for companion in player.companions where owners[companion.id] == nil {
                owners[companion.id] = player.id
            }
        }
        return owners
    }

    public static func status(
        of tablePlayer: TablePlayerModel,
        roster: [PlayerGameModel],
        characterExists: Bool
    ) -> TablePlayerStatus {
        guard characterExists else { return .missing }
        if let claimant = claimant(of: tablePlayer, roster: roster) {
            return .claimed(by: claimant)
        }
        return tablePlayer.isEnabled ? .active : .disabled
    }

    /// Who plays the Character of `candidate` ahead of it: a connected player, or the player
    /// who brought it along as an earlier companion. Returns that player's name.
    static func claimant(of candidate: TablePlayerModel, roster: [PlayerGameModel]) -> String? {
        let players = roster.filter { $0.type != .observer }
        if let player = players.first(where: { $0.characterId == candidate.characterId }) {
            return player.name
        }
        for player in players where player.type == .player {
            for companion in player.companions where companion.isEnabled {
                if companion.id == candidate.id { return nil }
                if companion.characterId == candidate.characterId { return player.name }
            }
        }
        return nil
    }

    /// Appends a table player for every Character not in `tablePlayers` yet, keeping the order.
    /// `excluded` Characters are never added (a player's own Character is no companion).
    public static func adding(
        characterIds: [UUID],
        to tablePlayers: [TablePlayerModel],
        excluding excluded: Set<UUID> = []
    ) -> [TablePlayerModel] {
        var result = tablePlayers
        var known = Set(tablePlayers.map(\.characterId)).union(excluded)
        for characterId in characterIds where known.insert(characterId).inserted {
            result.append(TablePlayerModel(characterId: characterId))
        }
        return result
    }
}

public extension KeyedDecodingContainer {
    /// The companions a peer sent. A list longer than `PlayerGameModel.maximumCompanions` is
    /// refused before any element is decoded: no honest device sends one, and the roster entry
    /// travels in every message. See CODE_AUDIT_24 §6.6.
    func decodeCompanions(forKey key: Key) throws -> [TablePlayerModel] {
        guard contains(key), try !decodeNil(forKey: key) else { return [] }
        var list = try nestedUnkeyedContainer(forKey: key)
        if let count = list.count, count > PlayerGameModel.maximumCompanions {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "More than \(PlayerGameModel.maximumCompanions) companions"
            )
        }
        var companions: [TablePlayerModel] = []
        while !list.isAtEnd {
            companions.append(try list.decode(TablePlayerModel.self))
        }
        return companions
    }
}
