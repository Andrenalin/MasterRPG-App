// @copyright André Trettin

import CoreRPG
import Foundation

// The statistics test and preview fixture, moved out of `GameStatisticsTypes.swift`.
// See CODE_AUDIT_29 §9.7.
#if DEBUG
private enum GameStatisticsFixture {
    static let sessionId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    static let participantId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    static let characterId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
    static let adventureId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
    static let eventId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5))
    static let date = Date(timeIntervalSince1970: 1_704_067_200)
}

extension GameStatisticSessionDraft {
    static func fixture(
        id: UUID = GameStatisticsFixture.sessionId,
        startedAt: Date = GameStatisticsFixture.date,
        role: GameStatisticRole = .player,
        localParticipantId: UUID = GameStatisticsFixture.participantId,
        participants: [GameStatisticParticipantDraft] = [.fixture()]
    ) -> Self {
        Self(
            id: id,
            startedAt: startedAt,
            role: role,
            localParticipantId: localParticipantId,
            localName: "Test Player",
            characterId: GameStatisticsFixture.characterId,
            characterName: "Test Hero",
            adventureId: GameStatisticsFixture.adventureId,
            adventureTitle: "Test Adventure",
            masterId: nil,
            masterName: "Test Game Master",
            isDemo: false,
            participants: participants
        )
    }
}

extension GameStatisticParticipantDraft {
    static func fixture(
        participantId: UUID = GameStatisticsFixture.participantId,
        characterId: UUID? = GameStatisticsFixture.characterId,
        name: String = "Test Player",
        characterName: String = "Test Hero",
        role: GameStatisticRole = .player,
        isLocal: Bool = true,
        isGameMaster: Bool = false
    ) -> Self {
        Self(
            participantId: participantId,
            characterId: characterId,
            name: name,
            characterName: characterName,
            role: role,
            isLocal: isLocal,
            isGameMaster: isGameMaster
        )
    }
}

extension GameStatisticEventDraft {
    static func fixture(
        id: UUID = GameStatisticsFixture.eventId,
        sessionId: UUID = GameStatisticsFixture.sessionId,
        occurredAt: Date = GameStatisticsFixture.date.addingTimeInterval(60),
        kind: GameStatisticEventKind = .diceRolled,
        outcome: GameStatisticDiceOutcome = .critical,
        deduplicationKey: String = "test-event"
    ) -> Self {
        Self(
            id: id,
            sessionId: sessionId,
            occurredAt: occurredAt,
            kind: kind,
            direction: .outgoing,
            origin: .localNetwork,
            actorId: GameStatisticsFixture.participantId,
            actorCharacterId: GameStatisticsFixture.characterId,
            actorName: "Test Hero",
            targetId: nil,
            itemId: nil,
            itemName: "",
            module: .dice,
            messageTypeRaw: 0,
            actionRaw: 0,
            outcome: outcome,
            quantity: 1,
            numericValue: 20,
            resultValues: "20",
            checked: true,
            payloadByteCount: 128,
            messageCounter: 1,
            proxyCounter: 0,
            dataVersion: 1,
            success: true,
            deduplicationKey: deduplicationKey
        )
    }
}

extension GameStatisticSessionSnapshot {
    static func fixture(
        id: UUID = GameStatisticsFixture.sessionId,
        startedAt: Date = GameStatisticsFixture.date,
        duration: TimeInterval = 3_600,
        role: GameStatisticRole = .player,
        characterId: UUID? = GameStatisticsFixture.characterId,
        characterName: String = "Test Hero",
        adventureId: UUID? = GameStatisticsFixture.adventureId,
        adventureTitle: String = "Test Adventure",
        maxParticipantCount: Int = 4
    ) -> Self {
        Self(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            duration: duration,
            role: role,
            localName: "Test Player",
            characterId: characterId,
            characterName: characterName,
            adventureId: adventureId,
            adventureTitle: adventureTitle,
            masterName: "Test Game Master",
            maxParticipantCount: maxParticipantCount
        )
    }
}

extension GameStatisticParticipantSnapshot {
    static func fixture(
        id: UUID = GameStatisticsFixture.participantId,
        sessionId: UUID = GameStatisticsFixture.sessionId,
        participantId: UUID = GameStatisticsFixture.participantId,
        characterId: UUID? = GameStatisticsFixture.characterId,
        name: String = "Remote Player",
        characterName: String = "Remote Hero",
        connectedDuration: TimeInterval = 3_600,
        isLocal: Bool = false
    ) -> Self {
        Self(
            id: id,
            sessionId: sessionId,
            participantId: participantId,
            characterId: characterId,
            name: name,
            characterName: characterName,
            role: .player,
            connectedDuration: connectedDuration,
            joinCount: 1,
            isLocal: isLocal
        )
    }
}

extension GameStatisticEventSnapshot {
    static func fixture(
        id: UUID = GameStatisticsFixture.eventId,
        sessionId: UUID = GameStatisticsFixture.sessionId,
        kind: GameStatisticEventKind = .diceRolled,
        direction: GameStatisticDirection = .outgoing,
        origin: GameStatisticOrigin = .localNetwork,
        actorId: UUID? = GameStatisticsFixture.participantId,
        module: NetworkModules = .dice,
        outcome: GameStatisticDiceOutcome = .critical,
        quantity: Int = 1,
        payloadByteCount: Int64 = 128
    ) -> Self {
        Self(
            id: id,
            sessionId: sessionId,
            occurredAt: GameStatisticsFixture.date.addingTimeInterval(60),
            kind: kind,
            direction: direction,
            origin: origin,
            actorName: "Test Hero",
            actorId: actorId,
            module: module,
            outcome: outcome,
            quantity: quantity,
            numericValue: 20,
            payloadByteCount: payloadByteCount,
            success: true
        )
    }
}
#endif
