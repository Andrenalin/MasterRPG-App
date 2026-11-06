// @copyright André Trettin

import AdventureRPG
import CoreRPG
import Foundation

extension GameRoot {
    /// Whether a screen offers the Players panel: the game master's player list, or a player's
    /// companions. Observers and proxies have none. See CODE_AUDIT_24 §9.13.
    func offersTablePlayers(isMaster: Bool) -> Bool {
        isMaster || gameModel.gameType == .player
    }

    /// Replaces the game master's table players: saves them to the adventure and gives the
    /// enabled ones player pins (or takes the pins of the others away) on every game map.
    func updateTablePlayers(_ tablePlayers: [TablePlayerModel]) {
        guard gameModel.gameConfig.isMaster, gameModel.tablePlayers != tablePlayers else { return }
        gameModel.tablePlayers = tablePlayers
        if let adventureId = gameModel.gameConfig.master.adventureId {
            adventureRoot.adventureGameControllable.saveTablePlayers(tablePlayers, for: adventureId)
        }
        scheduleNetworkAction { [weak self] in
            await self?.gameModel.masterController?.resetPlayers()
        }
    }

    /// Lets the connected device `deviceId` (a player or an observer) move the player pin
    /// `pinId`, or takes that away. The pin's own player always moves it.
    func setPinController(_ deviceId: UUID, for pinId: UUID, isEnabled: Bool) {
        guard gameModel.gameConfig.isMaster, deviceId != pinId else { return }
        var controllers = gameModel.pinControllers[pinId] ?? []
        let changed = isEnabled ? controllers.insert(deviceId).inserted : controllers.remove(deviceId) != nil
        guard changed else { return }
        // Kept when empty: a companion without an entry falls back to its owner.
        gameModel.pinControllers[pinId] = controllers
        scheduleNetworkAction { [weak self] in
            await self?.gameModel.masterController?.resetPlayers()
        }
    }

    /// The panel's model; its closures hold the root weakly, never a view.
    func makeTablePlayersModel() -> TablePlayersModel {
        TablePlayersModel { [weak self] in
            self?.gameModel.tablePlayers ?? []
        } update: { [weak self] tablePlayers in
            self?.updateTablePlayers(tablePlayers)
        }
    }

    /// The panel's model for a player: the companions it brings along.
    func makeCompanionsModel() -> TablePlayersModel {
        let model = TablePlayersModel { [weak self] in
            self?.gameModel.gamePlayer.companions ?? []
        } update: { [weak self] companions in
            self?.updateCompanions(companions)
        } excludedCharacterIds: { [weak self] in
            self?.gameModel.selectedCharacter.map { [$0] } ?? []
        }
        model.maximumCount = PlayerGameModel.maximumCompanions
        return model
    }
}

// MARK: - Companions

extension GameRoot {
    /// Replaces this player's companions: saves them for its Character and tells the game
    /// master, which gives the enabled ones player pins. Players only.
    func updateCompanions(_ companions: [TablePlayerModel], defaults: UserDefaults = .standard) {
        guard !gameModel.gameConfig.isMaster,
              gameModel.gameType == .player,
              let index = gameModel.gameRoster.players.firstIndex(where: { $0.id == gameModel.gameConfig.id })
        else { return }
        let companions = Array(companions.prefix(PlayerGameModel.maximumCompanions))
        guard gameModel.gameRoster.players[index].companions != companions else { return }
        gameModel.gameRoster.players[index].companions = companions
        if let characterId = gameModel.selectedCharacter {
            Self.storeCompanions(companions, for: characterId, defaults: defaults)
        }
        scheduleNetworkAction { [weak self] in
            await self?.gameModel.playerController?.announceCompanions()
        }
    }

    /// The companions saved for the player's Character `characterId`.
    static func storedCompanions(for characterId: UUID?, defaults: UserDefaults = .standard) -> [TablePlayerModel] {
        guard let characterId,
              let data = (defaults.dictionary(forKey: GameStorageKeys.playerCompanions) as? [String: Data])?[characterId.uuidString],
              let companions = try? JSONDecoder().decode([TablePlayerModel].self, from: data)
        else { return [] }
        return Array(companions.prefix(PlayerGameModel.maximumCompanions))
    }

    static func storeCompanions(_ companions: [TablePlayerModel], for characterId: UUID, defaults: UserDefaults = .standard) {
        var stored = defaults.dictionary(forKey: GameStorageKeys.playerCompanions) as? [String: Data] ?? [:]
        if companions.isEmpty {
            stored[characterId.uuidString] = nil
        } else if let data = try? JSONEncoder().encode(companions) {
            stored[characterId.uuidString] = data
        }
        defaults.set(stored, forKey: GameStorageKeys.playerCompanions)
    }
}
