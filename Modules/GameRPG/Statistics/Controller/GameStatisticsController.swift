// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation

struct GameStatisticsController: Sendable {
    static let minimumCountedSessionDuration: TimeInterval = 15 * 60
    /// Roles whose games are never recorded: an observer or proxy only relays someone else's game.
    static let uncountedRoles: Set<GameStatisticRole> = [.observer, .proxy]

    func eventDraft(
        for model: GameNetworkModel,
        sessionId: UUID,
        localParticipantId: UUID,
        direction: GameStatisticDirection,
        origin: GameMessageOrigin,
        occurredAt: Date = .now
    ) -> GameStatisticEventDraft {
        let diceResult = model.data.type == .dice ? DiceResultModel.decodeData(of: model.data.data) : nil
        let kind = eventKind(for: model, diceResult: diceResult)
        let outcome = diceOutcome(for: diceResult)
        let deduplicationKey = deduplicationKey(for: model, direction: direction)

        return GameStatisticEventDraft(
            id: UUID(),
            sessionId: sessionId,
            occurredAt: diceResult?.timestamp ?? occurredAt,
            kind: kind,
            direction: direction,
            origin: GameStatisticOrigin(origin),
            actorId: model.sender.id,
            actorCharacterId: model.sender.characterId,
            actorName: model.sender.name,
            targetId: model.targetId,
            itemId: model.data.id,
            itemName: "",
            module: model.data.type,
            messageTypeRaw: Int16(clamping: model.type.rawValue),
            actionRaw: Int16(clamping: model.subType.rawValue),
            outcome: outcome,
            quantity: 1,
            numericValue: Double(diceResult?.sum ?? 0),
            resultValues: diceResult?.values ?? "",
            checked: diceResult?.checked ?? false,
            payloadByteCount: Int64(model.data.data?.count ?? 0),
            messageCounter: Int64(model.counter),
            proxyCounter: Int64(model.proxyCounter),
            dataVersion: Int32(clamping: model.data.version),
            success: model.subType != .failed,
            deduplicationKey: deduplicationKey
        )
    }

    func participants(
        from model: GameNetworkModel,
        localParticipantId: UUID
    ) -> [GameStatisticParticipantDraft] {
        var players = model.masterState?.players ?? []
        if !players.contains(where: { $0.id == model.sender.id }) {
            players.append(model.sender.playerModel)
        }

        if model.sender.isMaster,
           !players.contains(where: { $0.id == model.masterId }) {
            players.append(PlayerGameModel(id: model.masterId, type: .master, name: model.sender.name))
        }

        var participantIDs = Set<UUID>()
        return players.compactMap { player in
            guard participantIDs.insert(player.id).inserted else { return nil }
            return participantDraft(player: player, localParticipantId: localParticipantId)
        }
    }

    func participantDraft(player: PlayerGameModel, localParticipantId: UUID) -> GameStatisticParticipantDraft {
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

    func summary(
        from dataSet: GameStatisticsDataSet,
        configuration: GameStatisticsDashboardConfiguration,
        calendar: Calendar = .autoupdatingCurrent
    ) -> GameStatisticsSummary {
        let sessions = dataSet.sessions.filter {
            $0.duration >= Self.minimumCountedSessionDuration && !Self.uncountedRoles.contains($0.role)
        }
        let countedSessionIDs = Set(sessions.map(\.id))
        let events = dataSet.events.filter { countedSessionIDs.contains($0.sessionId) }
        let participants = dataSet.participants.filter { countedSessionIDs.contains($0.sessionId) }
        let totalDuration = sessions.reduce(0) { $0 + $1.duration }
        let diceEvents = events.filter { $0.kind == .diceRolled }

        return GameStatisticsSummary(
            sessionCount: sessions.count,
            totalDuration: totalDuration,
            averageDuration: sessions.isEmpty ? 0 : totalDuration / Double(sessions.count),
            longestDuration: sessions.map(\.duration).max() ?? 0,
            gameMasterDuration: sessions.filter { $0.role == .gameMaster }.reduce(0) { $0 + $1.duration },
            playerDuration: sessions.filter { $0.role == .player }.reduce(0) { $0 + $1.duration },
            diceRollCount: diceEvents.reduce(0) { $0 + $1.quantity },
            criticalCount: diceEvents.filter { $0.outcome == .critical }.reduce(0) { $0 + $1.quantity },
            fumbleCount: diceEvents.filter { $0.outcome == .fumble }.reduce(0) { $0 + $1.quantity },
            payloadByteCount: events.reduce(0) { $0 + $1.payloadByteCount },
            activity: activityPoints(sessions: sessions, granularity: configuration.granularity, calendar: calendar),
            schedule: heatMapPoints(sessions: sessions, calendar: calendar),
            roles: categoryPoints(
                sessions: sessions,
                key: { String($0.role.rawValue) },
                title: { $0.role.title }
            ),
            characters: categoryPoints(
                sessions: sessions.filter { $0.characterId != nil || !$0.characterName.isEmpty },
                key: { $0.characterId?.uuidString ?? $0.characterName },
                title: { $0.characterName.isEmpty ? String(localized: "Unknown Character", bundle: .module) : $0.characterName }
            ),
            adventures: categoryPoints(
                sessions: sessions.filter { $0.adventureId != nil || !$0.adventureTitle.isEmpty },
                key: { $0.adventureId?.uuidString ?? $0.adventureTitle },
                title: { $0.adventureTitle.isEmpty ? String(localized: "Unknown Adventure", bundle: .module) : $0.adventureTitle }
            ),
            diceOutcomes: diceOutcomePoints(events: diceEvents),
            modules: modulePoints(events: events),
            party: participantPoints(participants: participants),
            network: networkPoints(events: events),
            recentSessions: Array(sessions.sorted { $0.startedAt > $1.startedAt }.prefix(10))
        )
    }

    private func eventKind(for model: GameNetworkModel, diceResult: DiceResultModel?) -> GameStatisticEventKind {
        if diceResult != nil { return .diceRolled }
        if model.subType == .ok { return .deliveryAcknowledged }
        if model.subType == .failed { return .deliveryFailed }
        if model.subType == .playAudio { return .audioPlayed }

        if model.data.type == .map {
            return model.type == .reveal && model.subType == .show
                ? .contentShared
                : .message
        }

        let sharingActions: Set<RPGMessageActionType> = [.show, .spaceTransform]
        if sharingActions.contains(model.subType), model.data.type != .game {
            return .contentShared
        }
        return .message
    }

    private func diceOutcome(for result: DiceResultModel?) -> GameStatisticDiceOutcome {
        guard let result else { return .none }
        return switch result.result {
        case .coup: .critical
        case .fumble: .fumble
        case .rolled: .rolled
        case .notRolled: .notRolled
        }
    }

    private func deduplicationKey(for model: GameNetworkModel, direction: GameStatisticDirection) -> String {
        guard model.counter > 0 else { return "" }
        return [
            String(direction.rawValue),
            model.sender.id.uuidString,
            String(model.counter),
            String(model.proxyCounter),
            String(model.type.rawValue),
            String(model.subType.rawValue),
            model.data.id.uuidString,
            String(model.data.type.rawValue),
            String(model.data.version),
            model.data.data == nil ? "reference" : "payload"
        ].joined(separator: "|")
    }

    private func activityPoints(
        sessions: [GameStatisticSessionSnapshot],
        granularity: GameStatisticsGranularity,
        calendar: Calendar
    ) -> [GameStatisticTimePoint] {
        var durationByDate: [Date: TimeInterval] = [:]
        var sessionsByDate: [Date: Int] = [:]

        for session in sessions {
            guard let startBucket = calendar.dateInterval(of: granularity.calendarComponent, for: session.startedAt)?.start else { continue }
            sessionsByDate[startBucket, default: 0] += 1
            splitInterval(start: session.startedAt, end: session.endedAt, component: granularity.calendarComponent, calendar: calendar) { date, duration in
                durationByDate[date, default: 0] += duration
            }
        }

        return Set(durationByDate.keys).union(sessionsByDate.keys).sorted().map { date in
            GameStatisticTimePoint(
                date: date,
                duration: durationByDate[date, default: 0],
                sessionCount: sessionsByDate[date, default: 0]
            )
        }
    }

    private func heatMapPoints(
        sessions: [GameStatisticSessionSnapshot],
        calendar: Calendar
    ) -> [GameStatisticHeatMapPoint] {
        var durationByCell: [String: TimeInterval] = [:]
        for session in sessions {
            splitInterval(start: session.startedAt, end: session.endedAt, component: .hour, calendar: calendar) { date, duration in
                let weekday = calendar.component(.weekday, from: date)
                let hour = calendar.component(.hour, from: date)
                durationByCell["\(weekday)-\(hour)", default: 0] += duration
            }
        }
        return durationByCell.compactMap { key, duration in
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return GameStatisticHeatMapPoint(weekday: parts[0], hour: parts[1], duration: duration)
        }
        .sorted { ($0.weekday, $0.hour) < ($1.weekday, $1.hour) }
    }

    private func splitInterval(
        start: Date,
        end: Date,
        component: Calendar.Component,
        calendar: Calendar,
        body: (Date, TimeInterval) -> Void
    ) {
        var cursor = start
        let safeEnd = max(start, end)
        while cursor < safeEnd,
              let bucket = calendar.dateInterval(of: component, for: cursor) {
            let segmentEnd = min(bucket.end, safeEnd)
            body(bucket.start, max(0, segmentEnd.timeIntervalSince(cursor)))
            guard segmentEnd > cursor else { break }
            cursor = segmentEnd
        }
    }

    private func categoryPoints(
        sessions: [GameStatisticSessionSnapshot],
        key: (GameStatisticSessionSnapshot) -> String,
        title: (GameStatisticSessionSnapshot) -> String
    ) -> [GameStatisticCategoryPoint] {
        var aggregates: [String: (title: String, duration: TimeInterval, count: Int)] = [:]
        for session in sessions {
            let itemKey = key(session)
            var aggregate = aggregates[itemKey] ?? (title(session), 0, 0)
            aggregate.duration += session.duration
            aggregate.count += 1
            aggregates[itemKey] = aggregate
        }
        return aggregates.map { itemKey, aggregate in
            GameStatisticCategoryPoint(key: itemKey, title: aggregate.title, value: aggregate.duration, count: aggregate.count)
        }
        .sorted { $0.value > $1.value }
    }

    private func diceOutcomePoints(events: [GameStatisticEventSnapshot]) -> [GameStatisticCategoryPoint] {
        Dictionary(grouping: events.filter { $0.outcome != .none && $0.outcome != .notRolled }, by: \.outcome)
            .map { outcome, events in
                let count = events.reduce(0) { $0 + $1.quantity }
                return GameStatisticCategoryPoint(key: String(outcome.rawValue), title: outcome.title, value: Double(count), count: count)
            }
            .sorted { $0.count > $1.count }
    }

    private func modulePoints(events: [GameStatisticEventSnapshot]) -> [GameStatisticCategoryPoint] {
        let sharedEvents = events.filter { $0.kind == .contentShared || $0.kind == .audioPlayed }
        return Dictionary(grouping: sharedEvents, by: \.module)
            .map { module, events in
                let count = events.reduce(0) { $0 + $1.quantity }
                return GameStatisticCategoryPoint(key: String(module.rawValue), title: module.title, value: Double(count), count: count)
            }
            .sorted { $0.count > $1.count }
    }

    private func participantPoints(participants: [GameStatisticParticipantSnapshot]) -> [GameStatisticCategoryPoint] {
        let remote = participants.filter { !$0.isLocal }
        var aggregates: [String: (title: String, duration: TimeInterval, count: Int)] = [:]
        for participant in remote {
            let key = participant.characterId?.uuidString ?? participant.participantId.uuidString
            let title = participant.characterName.isEmpty ? participant.name : participant.characterName
            var aggregate = aggregates[key] ?? (title, 0, 0)
            aggregate.duration += participant.connectedDuration
            aggregate.count += 1
            aggregates[key] = aggregate
        }
        return aggregates.map { key, aggregate in
            GameStatisticCategoryPoint(key: key, title: aggregate.title, value: aggregate.duration, count: aggregate.count)
        }
        .sorted { $0.value > $1.value }
    }

    private func networkPoints(events: [GameStatisticEventSnapshot]) -> [GameStatisticCategoryPoint] {
        Dictionary(grouping: events, by: \.origin)
            .map { origin, events in
                let count = events.reduce(0) { $0 + $1.quantity }
                return GameStatisticCategoryPoint(
                    key: String(origin.rawValue),
                    title: originTitle(origin),
                    value: Double(events.reduce(0) { $0 + $1.payloadByteCount }),
                    count: count
                )
            }
            .sorted { $0.count > $1.count }
    }

    private func originTitle(_ origin: GameStatisticOrigin) -> String {
        switch origin {
        case .local: String(localized: "Local", bundle: .module)
        case .localNetwork: String(localized: "Local Network", bundle: .module)
        case .proxy: String(localized: "Proxy", bundle: .module)
        case .sharePlay: String(localized: "SharePlay", bundle: .module)
        case .fileTransfer: String(localized: "File Transfer", bundle: .module)
        }
    }
}
