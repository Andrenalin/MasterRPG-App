// @copyright André Trettin

import CoreData
import CoreRPG
import Foundation
import Observation
import os.log

@MainActor @Observable
final class GameStatisticsModel: Sendable {
    private enum DefaultsKey {
        static let collectionEnabled = "GameRPG.statistics.collectionEnabled"
        static let dashboardConfiguration = "GameRPG.statistics.dashboardConfiguration"
    }

    var summary: GameStatisticsSummary = .empty
    /// Every completed game regardless of the dashboard filter; filled by `loadAllSessions()`.
    private(set) var allSessions: [GameStatisticSessionSnapshot] = []
    var configuration: GameStatisticsDashboardConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            persistConfiguration()
        }
    }
    private(set) var isCollectionEnabled: Bool
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var context: NSManagedObjectContext?
    @ObservationIgnored private var setupTask: Task<Void, Never>?
    @ObservationIgnored private var activeSessionId: UUID?
    /// Set once the final flush is done and the session is being completed: an event recorded
    /// now would be queued for a session `recordEvents` already skips. See CODE_AUDIT_20 §3.4.
    @ObservationIgnored private var isClosingSession = false
    @ObservationIgnored private var activeLocalParticipantId: UUID?
    @ObservationIgnored private let dataController = GameStatisticsDataController()
    @ObservationIgnored private let statisticsController = GameStatisticsController()
    /// Events waiting for the next batched write, and the roster last written to the store.
    /// See CODE_AUDIT_17 §7.1.
    @ObservationIgnored private var pendingEvents: [(draft: GameStatisticEventDraft, participant: GameStatisticParticipantDraft?)] = []
    @ObservationIgnored private var pendingRoster: [GameStatisticParticipantDraft]?
    @ObservationIgnored private var lastCheckpointedRosterIds: Set<UUID> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    /// The flush a full buffer started, while it runs.
    @ObservationIgnored private var bufferFlushTask: Task<Void, Never>?
    /// Serializes flushes: `finishSession`/`beginSession` await any flush still in flight
    /// instead of finding an empty buffer and running ahead of it. See CODE_AUDIT_18 §3.10.
    @ObservationIgnored private var flushChain: Task<Void, Never>?
    /// Consecutive failed flushes of the same batch; after `maximumFlushRetries` it is dropped.
    @ObservationIgnored private var failedFlushAttempts = 0
    private static let maximumFlushRetries = 3
    private static let flushInterval: Duration = .seconds(2)
    private static let maximumBufferedEvents = 100
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

    func setUp(context shared: NSManagedObjectContext) {
        let context = Self.statisticsContext(sharing: shared)
        self.context = context
        setupTask?.cancel()
        setupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await dataController.recoverInterruptedSessions(in: context)
                await pruneShortSessions()
                await reloadAndReportAchievements()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// A context of its own on the store of `shared`: saving the shared context committed the
    /// other modules' pending edits along with the statistics, and one failing foreign object
    /// failed the statistics save. See CODE_AUDIT_29 §7.1.
    static func statisticsContext(sharing shared: NSManagedObjectContext) -> NSManagedObjectContext {
        guard let coordinator = shared.persistentStoreCoordinator else { return shared }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.name = "statistics_context"
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        // The same author as the shared context, so persistent-history processing treats the
        // statistics saves as this app's own, as before.
        context.transactionAuthor = shared.transactionAuthor
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    func beginSession(_ draft: GameStatisticSessionDraft) async {
        guard isCollectionEnabled,
              !draft.isDemo,
              !GameStatisticsController.uncountedRoles.contains(draft.role),
              let context
        else { return }
        await flushPendingEvents()
        lastCheckpointedRosterIds = []
        do {
            if let activeSessionId {
                try await dataController.finishLeftoverSession(id: activeSessionId, reason: .interrupted, notAfter: draft.startedAt, in: context)
            }
            try await dataController.beginSession(draft, in: context)
            activeSessionId = draft.id
            activeLocalParticipantId = draft.localParticipantId
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkpoint(
        participants: [GameStatisticParticipantDraft],
        at date: Date = .now,
        details: GameStatisticSessionDetails? = nil,
        advancesActivity: Bool = true
    ) async {
        guard let context, let activeSessionId else { return }
        await flushPendingEvents()
        lastCheckpointedRosterIds = Set(participants.map(\.participantId))
        do {
            try await dataController.checkpointSession(id: activeSessionId, participants: participants, at: date, details: details, advancesActivity: advancesActivity, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Buffers the event synchronously; the persistence (a Core Data duplicate-check fetch plus
    /// insert) never runs in the latency of the game message that triggered it, including small,
    /// latency-sensitive ones like `.mapPin`/`.spaceTransform`: the buffer is written by the timer
    /// flush (`scheduleFlush`) or, when it fills, by a flush task this function does not await.
    /// Synchronous so a call neither suspends nor allocates a task per game message.
    /// See CODE_AUDIT_Game §7.1, CODE_AUDIT_26 §3.8.
    func record(
        _ model: GameNetworkModel,
        direction: GameStatisticDirection,
        origin: GameMessageOrigin,
        at date: Date = .now
    ) {
        guard isCollectionEnabled,
              context != nil,
              let activeSessionId,
              let activeLocalParticipantId
        else { return }
        guard !isClosingSession else {
            Logger.statistics.debug("Dropped a statistics event recorded while the session is closing")
            return
        }

        let draft = statisticsController.eventDraft(
            for: model,
            sessionId: activeSessionId,
            localParticipantId: activeLocalParticipantId,
            direction: direction,
            origin: origin,
            occurredAt: date
        )
        let participants = statisticsController.participants(from: model, localParticipantId: activeLocalParticipantId)
        pendingEvents.append((draft, participants.first(where: { $0.participantId == model.sender.id })))
        // Only a changed roster needs a checkpoint; the per-event participant sync already
        // keeps the sender's row current.
        if participants.count > 1, Set(participants.map(\.participantId)) != lastCheckpointedRosterIds {
            pendingRoster = participants
        }

        if pendingEvents.count >= Self.maximumBufferedEvents, bufferFlushTask == nil {
            // One full-buffer flush at a time: while a slow save runs, the events that fill the
            // buffer again wait for the timer instead of starting a task each. See CODE_AUDIT_28 §3.4.
            bufferFlushTask = Task { [weak self] in
                await self?.flushPendingEvents()
                self?.bufferFlushTask = nil
            }
        } else {
            scheduleFlush()
        }
    }

    /// Writes every buffered event (and a changed roster) with one save. Called on a timer, when
    /// the buffer fills, and before anything that reads or closes the session.
    func flushPendingEvents() async {
        flushTask?.cancel()
        flushTask = nil
        let previous = flushChain
        let flush = Task { @MainActor [weak self] in
            await previous?.value
            await self?.performFlush()
        }
        flushChain = flush
        await flush.value
    }

    private func performFlush() async {
        let batch = pendingEvents
        let roster = pendingRoster
        pendingEvents = []
        pendingRoster = nil
        guard let context, !batch.isEmpty || roster != nil else { return }
        // Only the step that failed is re-queued: once `recordEvents` saved, re-queuing the
        // batch for a failed checkpoint inserted events without a deduplication key twice.
        // See CODE_AUDIT_19 §3.17.
        var unsavedBatch = batch
        do {
            try await dataController.recordEvents(batch, in: context)
            unsavedBatch = []
            if let roster, let sessionId = batch.last?.draft.sessionId ?? activeSessionId {
                try await dataController.checkpointSession(
                    id: sessionId,
                    participants: roster,
                    at: batch.last?.draft.occurredAt ?? .now,
                    in: context
                )
                lastCheckpointedRosterIds = Set(roster.map(\.participantId))
            }
            failedFlushAttempts = 0
        } catch {
            errorMessage = error.localizedDescription
            // The shared context can fail because of another module's object; put the batch
            // back (in front of newer events) and retry, instead of losing it, up to a cap.
            // See CODE_AUDIT_18 §3.10.
            failedFlushAttempts += 1
            if failedFlushAttempts <= Self.maximumFlushRetries {
                pendingEvents.insert(contentsOf: unsavedBatch, at: 0)
                if pendingRoster == nil { pendingRoster = roster }
                scheduleFlush()
            } else {
                Logger.statistics.error("Dropped \(unsavedBatch.count, privacy: .public) statistics events after \(Self.maximumFlushRetries, privacy: .public) failed saves")
                failedFlushAttempts = 0
            }
        }
    }

    /// Flushes after `flushInterval` unless a flush is already scheduled. Also retries a failed
    /// flush, which used to wait for the next event to arrive. See CODE_AUDIT_19 §3.17.
    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            guard !Task.isCancelled else { return }
            await self?.flushPendingEvents()
        }
    }

    private var hasPendingWrites: Bool {
        !pendingEvents.isEmpty || pendingRoster != nil
    }

    /// Flushes, retrying failed saves right away, before the session is marked complete:
    /// `recordEvents` skips events of a completed session. Whatever still cannot be saved is
    /// dropped with a log instead of silently. See CODE_AUDIT_19 §3.17.
    private func flushBeforeCompletingSession() async {
        await flushPendingEvents()
        var retries = 0
        while hasPendingWrites, retries < Self.maximumFlushRetries {
            retries += 1
            await flushPendingEvents()
        }
        guard hasPendingWrites else { return }
        flushTask?.cancel()
        flushTask = nil
        Logger.statistics.error("Dropped \(self.pendingEvents.count, privacy: .public) statistics events that could not be saved before the session ended")
        pendingEvents = []
        pendingRoster = nil
        failedFlushAttempts = 0
    }

    func participantLeft(id: UUID, at date: Date = .now) async {
        guard let context, let activeSessionId else { return }
        await flushPendingEvents()
        do {
            try await dataController.participantLeft(
                sessionId: activeSessionId,
                participantId: id,
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
        guard let context, let activeSessionId else { return }
        await flushBeforeCompletingSession()
        isClosingSession = true
        defer { isClosingSession = false }
        do {
            try await dataController.finishSession(id: activeSessionId, at: date, reason: reason, in: context)
            self.activeSessionId = nil
            activeLocalParticipantId = nil
            await pruneShortSessions()
            await reloadAndReportAchievements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) async {
        guard let context else { return }
        await flushPendingEvents()
        isLoading = true
        defer { isLoading = false }
        do {
            let interval = configuration.dateRange.interval(endingAt: now, calendar: calendar)
            let dataSet = try await dataController.fetchDataSet(
                interval: interval,
                direction: configuration.direction,
                in: context
            )
            let newSummary = await statisticsController.summaryOffMainActor(
                from: dataSet,
                configuration: configuration,
                calendar: calendar
            )
            // Published only when something changed, so the charts do not redraw for a reload
            // that found the same data.
            if summary != newSummary {
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
            // Events still queued belong to the running game and must not be flushed into nothing.
            await flushPendingEvents()
            try await dataController.deleteAll(keeping: activeSessionId, in: context)
            summary = .empty
            allSessions = []
            errorMessage = nil
            if activeSessionId != nil {
                await reload()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Repairs the stored statistics (removes games under `GameStatisticsController.minimumCountedSessionDuration` and observer/proxy games) and
    /// reloads the dashboard. Run by the pull-to-refresh of the report pages.
    func repair() async {
        await flushPendingEvents()
        await pruneShortSessions()
        await reload()
        if !allSessions.isEmpty { await loadAllSessions() }
    }

    private func pruneShortSessions() async {
        guard let context else { return }
        do {
            try await dataController.deleteSessions(
                shorterThan: GameStatisticsController.minimumCountedSessionDuration,
                orRoles: GameStatisticsController.uncountedRoles,
                in: context
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAllSessions() async {
        guard let context else { return }
        await flushPendingEvents()
        do {
            allSessions = try await dataController.fetchSessions(in: context)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSessions(ids: Set<UUID>) async {
        guard let context, !ids.isEmpty else { return }
        do {
            try await dataController.deleteSessions(ids: ids, in: context)
            allSessions.removeAll { ids.contains($0.id) }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistConfiguration() {
        guard let data = try? JSONCoding.encoder.encode(configuration) else { return }
        defaults.set(data, forKey: DefaultsKey.dashboardConfiguration)
    }

    /// The reload and the achievements of a game start or end from one fetch of the whole history
    /// (the dashboard range is cut from it in memory) instead of two. See CODE_AUDIT_28 §7.3.
    func reloadAndReportAchievements(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) async {
        guard let context else { return }
        await flushPendingEvents()
        isLoading = true
        defer { isLoading = false }
        do {
            let everything = try await dataController.fetchDataSet(interval: nil, direction: nil, in: context)
            let interval = configuration.dateRange.interval(endingAt: now, calendar: calendar)
            let newSummary = await statisticsController.summaryOffMainActor(
                from: everything.filtered(interval: interval, direction: configuration.direction),
                configuration: configuration,
                calendar: calendar
            )
            if summary != newSummary {
                summary = newSummary
            }
            errorMessage = nil
            await reportAchievements(from: everything)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reportAchievements(from dataSet: GameStatisticsDataSet) async {
        guard let achievementReporter else { return }
        var achievementConfiguration = GameStatisticsDashboardConfiguration.default
        achievementConfiguration.dateRange = .allTime
        let achievementSummary = await statisticsController.summaryOffMainActor(
            from: dataSet,
            configuration: achievementConfiguration,
            calendar: .autoupdatingCurrent
        )
        await achievementReporter(achievementSummary)
    }
}

extension Logger {
    static let statistics = Logger(subsystem: subsystem, category: "GameStatistics")
}
