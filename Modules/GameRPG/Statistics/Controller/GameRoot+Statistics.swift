// @copyright André Trettin

import CoreData
import CoreRPG
import CharacterRPG
import Foundation

extension GameRoot {
    public func setUpStatistics(context: NSManagedObjectContext) {
        statisticsModel.setUp(context: context)
        gameCenterController.authenticate()
    }

    func beginStatisticsSession(for gameType: GameType, at date: Date = .now) async {
        let localParticipantID = gameModel.gameConfig.id
        let localPlayer = gameModel.gamePlayer
        let characterID = gameType == .master ? nil : (localPlayer.characterId ?? gameModel.selectedCharacter)
        let characterName: String
        if let characterID {
            characterName = characterRoot.linkControllable.name(for: characterID)
        } else {
            characterName = ""
        }

        var players = gameModel.gameRoster.players
        let master = gameModel.gameConfig.master
        if !players.contains(where: { $0.id == master.id }) {
            players.append(PlayerGameModel(id: master.id, type: .master, name: master.name))
        }
        if !players.contains(where: { $0.id == localParticipantID }) {
            players.append(
                PlayerGameModel(
                    id: localParticipantID,
                    type: gameType,
                    name: gameType == .master ? master.name : gameModel.gameName,
                    characterId: characterID
                )
            )
        }

        let participants = players.map { player in
            GameStatisticParticipantDraft(
                participantID: player.id,
                characterID: player.characterId,
                name: player.name,
                characterName: player.characterId == nil ? "" : player.name,
                role: GameStatisticRole(gameType: player.type),
                isLocal: player.id == localParticipantID,
                isGameMaster: player.type == .master
            )
        }

        await statisticsModel.beginSession(
            GameStatisticSessionDraft(
                id: UUID(),
                startedAt: date,
                role: GameStatisticRole(gameType: gameType),
                localParticipantID: localParticipantID,
                localName: gameType == .master ? master.name : gameModel.gameName,
                characterID: characterID,
                characterName: characterName,
                adventureID: master.adventureId ?? gameModel.selectedAdventure,
                adventureTitle: master.adventureTitle ?? "",
                masterID: master.id,
                masterName: master.name,
                isDemo: gameType == .demo,
                participants: participants
            )
        )
    }

    func currentStatisticParticipants() -> [GameStatisticParticipantDraft] {
        let localParticipantID = gameModel.gameConfig.id
        var players = gameModel.gameRoster.players
        let master = gameModel.gameConfig.master
        if !players.contains(where: { $0.id == master.id }) {
            players.append(PlayerGameModel(id: master.id, type: .master, name: master.name))
        }
        return players.map { player in
            GameStatisticParticipantDraft(
                participantID: player.id,
                characterID: player.characterId,
                name: player.name,
                characterName: player.characterId == nil ? "" : player.name,
                role: GameStatisticRole(gameType: player.type),
                isLocal: player.id == localParticipantID,
                isGameMaster: player.type == .master
            )
        }
    }
}
