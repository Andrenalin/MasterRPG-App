// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import Observation

@MainActor @Observable
final class GameStatisticsModel: Sendable {
    private enum DefaultsKey {
        static let collectionEnabled = "GameRPG.statistics.collectionEnabled"
        static let dashboardConfiguration = "GameRPG.statistics.dashboardConfiguration"
    }

    var summary: GameStatisticsSummary = .empty
    var configuration: GameStatisticsDashboardConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            persistConfiguration()
        }
    }
    private(set) var isCollectionEnabled: Bool
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastCompletedSessionID: UUID?

    @ObservationIgnored private var context: NSManagedObjectContext?
    @ObservationIgnored private var setupTask: Task<Void, Never>?
    @ObservationIgnored private var activeSessionID: UUID?
    @ObservationIgnored private var activeLocalParticipantID: UUID?
    @ObservationIgnored private let dataController = GameStatisticsDataController()
    @ObservationIgnored private let statisticsController = GameStatisticsController()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var achievementReporter: (@MainActor @Sendable (GameStatisticsSummary) async -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: DefaultsKey.collectionEnabled) == nil {
            isCollectionEnabled = true
        } else {
            isCollectionEnabled = defaults.bool(forKey: DefaultsKey.collectionEnabled)
        }

        if let data = defaults.data(forKey: DefaultsKey.dashboardConfiguration),
           let saved = try? JSONCoding.decoder.decode(GameStatisticsDashboardConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = .default
        }
    }

    func setUp(context: NSManagedObjectContext) {
        self.context = context
        setupTask?.cancel()
        setupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await dataController.recoverInterruptedSessions(in: context)
                await reload()
                await reportAchievements()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func beginSession(_ draft: GameStatisticSessionDraft) async {
        guard isCollectionEnabled, !draft.isDemo, let context else { return }
        do {
            if let activeSessionID {
                try await dataController.finishSession(id: activeSessionID, at: draft.startedAt, reason: .interrupted, in: context)
            }
            try await dataController.beginSession(draft, in: context)
            activeSessionID = draft.id
            activeLocalParticipantID = draft.localParticipantID
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkpoint(participants: [GameStatisticParticipantDraft], at date: Date = .now) async {
        guard let context, let activeSessionID else { return }
        do {
            try await dataController.checkpointSession(id: activeSessionID, participants: participants, at: date, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fire-and-forget on purpose: persistence latency (a Core Data
    /// duplicate-check fetch plus insert) must never be serialized into the
    /// latency of the game message that triggered it, including small,
    /// latency-sensitive ones like `.mapPin`/`.spaceTransform`. The actual
    /// work runs in a detached child task this function does not await, so
    /// every existing `await ...record(...)` call site returns almost
    /// immediately without needing to change. See CODE_AUDIT_Game §7.1.
    func record(
        _ model: GameNetworkModel,
        direction: GameStatisticDirection,
        origin: GameMessageOrigin,
        at date: Date = .now
    ) async {
        Task { [weak self] in
            await self?.recordAndPersist(model, direction: direction, origin: origin, at: date)
        }
    }

    private func recordAndPersist(
        _ model: GameNetworkModel,
        direction: GameStatisticDirection,
        origin: GameMessageOrigin,
        at date: Date
    ) async {
        guard isCollectionEnabled,
              let context,
              let activeSessionID,
              let activeLocalParticipantID
        else { return }

        let draft = statisticsController.eventDraft(
            for: model,
            sessionId: activeSessionID,
            localParticipantID: activeLocalParticipantID,
            direction: direction,
            origin: origin,
            occurredAt: date
        )
        let participants = statisticsController.participants(from: model, localParticipantID: activeLocalParticipantID)

        do {
            try await dataController.recordEvent(
                draft,
                participant: participants.first(where: { $0.participantID == model.sender.id }),
                in: context
            )
            if participants.count > 1 {
                try await dataController.checkpointSession(
                    id: activeSessionID,
                    participants: participants,
                    at: draft.occurredAt,
                    in: context
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func participantLeft(id: UUID, at date: Date = .now) async {
        guard let context, let activeSessionID else { return }
        do {
            try await dataController.participantLeft(
                sessionID: activeSessionID,
                participantID: id,
                at: date,
                in: context
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finishSession(
        reason: GameStatisticSessionEndReason = .stopped,
        at date: Date = .now
    ) async {
        guard let context, let activeSessionID else { return }
        do {
            try await dataController.finishSession(id: activeSessionID, at: date, reason: reason, in: context)
            lastCompletedSessionID = activeSessionID
            self.activeSessionID = nil
            activeLocalParticipantID = nil
            await reload()
            await reportAchievements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) async {
        guard let context else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let interval = configuration.dateRange.interval(endingAt: now, calendar: calendar)
            let dataSet = try await dataController.fetchDataSet(
                interval: interval,
                direction: configuration.direction,
                in: context
            )
            let newSummary = statisticsController.summary(
                from: dataSet,
                configuration: configuration,
                calendar: calendar
            )
            if summary.sessionCount != newSummary.sessionCount ||
                summary.totalDuration != newSummary.totalDuration ||
                summary.diceRollCount != newSummary.diceRollCount ||
                summary.payloadByteCount != newSummary.payloadByteCount ||
                summary.recentSessions != newSummary.recentSessions {
                summary = newSummary
            } else {
                summary = newSummary
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCollectionEnabled(_ enabled: Bool) async {
        guard enabled != isCollectionEnabled else { return }
        if !enabled {
            await finishSession(reason: .stopped)
        }
        isCollectionEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.collectionEnabled)
    }

    func setAchievementReporter(
        _ reporter: @MainActor @escaping @Sendable (GameStatisticsSummary) async -> Void
    ) {
        achievementReporter = reporter
    }

    func setSection(_ section: GameStatisticsSection, isVisible: Bool) {
        if isVisible {
            configuration.hiddenSections.remove(section)
        } else {
            configuration.hiddenSections.insert(section)
        }
    }

    func moveSection(_ section: GameStatisticsSection, offset: Int) {
        guard let source = configuration.sectionOrder.firstIndex(of: section) else { return }
        let destination = min(max(0, source + offset), configuration.sectionOrder.index(before: configuration.sectionOrder.endIndex))
        guard source != destination else { return }
        var order = configuration.sectionOrder
        let moved = order.remove(at: source)
        order.insert(moved, at: destination)
        configuration.sectionOrder = order
    }

    func moveSections(fromOffsets source: IndexSet, toOffset destination: Int) {
        let order = configuration.sectionOrder
        guard !source.isEmpty,
              source.allSatisfy({ order.indices.contains($0) }),
              order.indices.contains(destination) || destination == order.endIndex
        else { return }

        let movedSections = source.map { order[$0] }
        var reordered = order
        for index in source.reversed() {
            reordered.remove(at: index)
        }

        let removedBeforeDestination = source.lazy.filter { $0 < destination }.count
        let insertionIndex = destination - removedBeforeDestination
        reordered.insert(contentsOf: movedSections, at: insertionIndex)

        guard reordered != order else { return }
        configuration.sectionOrder = reordered
    }

    func deleteAll() async {
        guard let context else { return }
        do {
            try await dataController.deleteAll(in: context)
            activeSessionID = nil
            activeLocalParticipantID = nil
            lastCompletedSessionID = nil
            summary = .empty
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSession(id: UUID) async {
        guard let context else { return }
        do {
            try await dataController.deleteSession(id: id, in: context)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistConfiguration() {
        guard let data = try? JSONCoding.encoder.encode(configuration) else { return }
        defaults.set(data, forKey: DefaultsKey.dashboardConfiguration)
    }

    private func reportAchievements() async {
        guard let context, let achievementReporter else { return }
        do {
            let dataSet = try await dataController.fetchDataSet(interval: nil, direction: nil, in: context)
            var achievementConfiguration = GameStatisticsDashboardConfiguration.default
            achievementConfiguration.dateRange = .allTime
            let achievementSummary = statisticsController.summary(
                from: dataSet,
                configuration: achievementConfiguration,
                calendar: .autoupdatingCurrent
            )
            await achievementReporter(achievementSummary)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
