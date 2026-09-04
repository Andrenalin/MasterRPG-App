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
        let localParticipantId = gameModel.gameConfig.id
        let localPlayer = gameModel.gamePlayer
        let characterId = gameType == .master ? nil : (localPlayer.characterId ?? gameModel.selectedCharacter)
        let characterName: String
        if let characterId {
            characterName = characterRoot.linkControllable.name(for: characterId)
        } else {
            characterName = ""
        }

        var players = gameModel.gameRoster.players
        let master = gameModel.gameConfig.master
        if !players.contains(where: { $0.id == master.id }) {
            players.append(PlayerGameModel(id: master.id, type: .master, name: master.name))
        }
        if !players.contains(where: { $0.id == localParticipantId }) {
            players.append(
                PlayerGameModel(
                    id: localParticipantId,
                    type: gameType,
                    name: gameType == .master ? master.name : gameModel.gameName,
                    characterId: characterId
                )
            )
        }

        let participants = players.map { player in
            GameStatisticParticipantDraft(
                participantId: player.id,
                characterId: player.characterId,
                name: player.name,
                characterName: player.characterId == nil ? "" : player.name,
                role: GameStatisticRole(gameType: player.type),
                isLocal: player.id == localParticipantId,
                isGameMaster: player.type == .master
            )
        }

        await statisticsModel.beginSession(
            GameStatisticSessionDraft(
                id: UUID(),
                startedAt: date,
                role: GameStatisticRole(gameType: gameType),
                localParticipantId: localParticipantId,
                localName: gameType == .master ? master.name : gameModel.gameName,
                characterId: characterId,
                characterName: characterName,
                adventureId: master.adventureId ?? gameModel.selectedAdventure,
                adventureTitle: master.adventureTitle ?? "",
                masterId: master.id,
                masterName: master.name,
                isDemo: gameType == .demo,
                participants: participants
            )
        )
    }

    func currentStatisticParticipants() -> [GameStatisticParticipantDraft] {
        let localParticipantId = gameModel.gameConfig.id
        var players = gameModel.gameRoster.players
        let master = gameModel.gameConfig.master
        if !players.contains(where: { $0.id == master.id }) {
            players.append(PlayerGameModel(id: master.id, type: .master, name: master.name))
        }
        return players.map { player in
            GameStatisticParticipantDraft(
                participantId: player.id,
                characterId: player.characterId,
                name: player.name,
                characterName: player.characterId == nil ? "" : player.name,
                role: GameStatisticRole(gameType: player.type),
                isLocal: player.id == localParticipantId,
                isGameMaster: player.type == .master
            )
        }
    }
}
