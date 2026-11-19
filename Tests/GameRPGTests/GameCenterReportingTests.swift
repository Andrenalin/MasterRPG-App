// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_TestGaps §5.14: what `GameCenterController` reports to Game Center and when.
/// `GKAchievement.report` needs a signed-in player, so the controller talks to a
/// `GameCenterService` and these tests give it a recording one.
@MainActor
@Suite("Game Center reporting")
struct GameCenterReportingTests {
    private final class RecordingService: GameCenterService {
        var isAuthenticated: Bool
        var existing: [GameCenterAchievementState]
        var loadError: (any Error)?
        var reportError: (any Error)?
        private(set) var loadCount = 0
        private(set) var reports: [[GameCenterAchievementUpdate]] = []

        init(isAuthenticated: Bool = true, existing: [GameCenterAchievementState] = []) {
            self.isAuthenticated = isAuthenticated
            self.existing = existing
        }

        func loadAchievements() async throws -> [GameCenterAchievementState] {
            loadCount += 1
            if let loadError { throw loadError }
            return existing
        }

        func report(_ updates: [GameCenterAchievementUpdate]) async throws {
            if let reportError { throw reportError }
            reports.append(updates)
        }
    }

    private struct ServiceFailure: LocalizedError {
        var errorDescription: String? { "Game Center is offline" }
    }

    private func summary(sessionCount: Int, hours: Double = 1) -> GameStatisticsSummary {
        let start = Date(timeIntervalSince1970: 1_704_153_600)
        let sessions = (0..<sessionCount).map { index in
            GameStatisticSessionSnapshot.fixture(
                id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index >> 8), UInt8(index & 0xff))),
                startedAt: start.addingTimeInterval(Double(index) * 86_400),
                duration: hours * 3_600
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return GameStatisticsController().summary(
            from: GameStatisticsDataSet(sessions: sessions, participants: [], events: []),
            configuration: .default,
            calendar: calendar
        )
    }

    private func controller(_ service: RecordingService) -> GameCenterController {
        GameCenterController(model: GameCenterModel(), service: service)
    }

    private func reportedIds(_ service: RecordingService) -> [String] {
        service.reports.flatMap { $0.map(\.identifier) }
    }

    // MARK: - When it reports

    @Test("Nothing is loaded or reported without a signed-in player")
    func unauthenticatedReportsNothing() async {
        let service = RecordingService(isAuthenticated: false)
        let controller = controller(service)

        await controller.reportAchievements(from: summary(sessionCount: 3))

        #expect(service.loadCount == 0)
        #expect(service.reports.isEmpty)
        #expect(!controller.model.isReportingAchievements)
    }

    @Test("A first game reports its achievement once, with the banner at 100 percent only")
    func firstGameIsReportedWithABanner() async {
        let service = RecordingService()
        let controller = controller(service)

        await controller.reportAchievements(from: summary(sessionCount: 1))

        #expect(service.reports.count == 1, "one report call for all achievements")
        let updates = service.reports.first ?? []
        let first = updates.first { $0.identifier == GameCenterAchievementEvaluator.Identifier.firstGame }
        #expect(first?.percentComplete == 100)
        #expect(first?.showsCompletionBanner == true)
        let regular = updates.first { $0.identifier == GameCenterAchievementEvaluator.Identifier.regularAdventurer }
        #expect(regular?.percentComplete == 10)
        #expect(regular?.showsCompletionBanner == false, "10 of 100 percent is progress, not a completion")
        #expect(Set(updates.map(\.identifier)).count == updates.count, "one update per achievement")
    }

    @Test("An achievement at zero is not reported")
    func zeroProgressIsNotReported() async {
        let service = RecordingService()
        let controller = controller(service)

        await controller.reportAchievements(from: summary(sessionCount: 1))

        let ids = reportedIds(service)
        #expect(!ids.contains(GameCenterAchievementEvaluator.Identifier.diceInitiate), "no dice were rolled")
        #expect(!ids.contains(GameCenterAchievementEvaluator.Identifier.criticalMoment))
        #expect(!ids.contains(GameCenterAchievementEvaluator.Identifier.storyteller), "no game master time")
        let bothSides = service.reports.first?.first { $0.identifier == GameCenterAchievementEvaluator.Identifier.bothSides }
        #expect(bothSides?.percentComplete == 50, "one side of two was played")
    }

    @Test("Without progress there is no report call at all")
    func emptySummaryReportsNothing() async {
        let service = RecordingService()
        let controller = controller(service)

        await controller.reportAchievements(from: summary(sessionCount: 0))

        #expect(service.loadCount == 1, "the existing achievements were loaded")
        #expect(service.reports.isEmpty)
        #expect(!controller.model.isReportingAchievements)
        #expect(controller.model.errorMessage == nil)
    }

    // MARK: - Deduplication

    @Test("What Game Center already holds is not reported again")
    func unchangedProgressIsNotReportedAgain() async {
        let service = RecordingService(existing: [
            GameCenterAchievementState(identifier: GameCenterAchievementEvaluator.Identifier.firstGame, percentComplete: 100),
            GameCenterAchievementState(identifier: GameCenterAchievementEvaluator.Identifier.regularAdventurer, percentComplete: 10)
        ])
        let controller = controller(service)

        await controller.reportAchievements(from: summary(sessionCount: 1))

        let ids = reportedIds(service)
        #expect(!ids.contains(GameCenterAchievementEvaluator.Identifier.firstGame))
        #expect(!ids.contains(GameCenterAchievementEvaluator.Identifier.regularAdventurer))
    }

    @Test("Reporting twice with the same summary reports the second time nothing new")
    func secondReportIsAMirror() async {
        let service = RecordingService()
        let controller = controller(service)
        let summary = summary(sessionCount: 1)

        await controller.reportAchievements(from: summary)
        // Game Center now holds what was reported.
        service.existing = (service.reports.first ?? []).map {
            GameCenterAchievementState(identifier: $0.identifier, percentComplete: $0.percentComplete)
        }
        await controller.reportAchievements(from: summary)

        #expect(service.reports.count == 1)
    }

    @Test("Progress that grew is reported, a lower one is never lowered")
    func onlyHigherProgressIsReported() {
        let progress = [
            GameCenterAchievementProgress(identifier: "a", percentComplete: 50),
            GameCenterAchievementProgress(identifier: "b", percentComplete: 20),
            GameCenterAchievementProgress(identifier: "c", percentComplete: 100),
            GameCenterAchievementProgress(identifier: "d", percentComplete: 0)
        ]
        let existing = [
            GameCenterAchievementState(identifier: "a", percentComplete: 30),
            GameCenterAchievementState(identifier: "b", percentComplete: 60),
            GameCenterAchievementState(identifier: "c", percentComplete: 100)
        ]

        let updates = GameCenterController.updates(for: progress, existing: existing)

        #expect(updates.map(\.identifier) == ["a"])
        #expect(updates.first?.percentComplete == 50)
        #expect(updates.first?.showsCompletionBanner == false)
    }

    @Test("Duplicate ids from Game Center do not trap, and the first one decides")
    func duplicateExistingIdsAreTolerated() {
        let progress = [GameCenterAchievementProgress(identifier: "a", percentComplete: 50)]
        let existing = [
            GameCenterAchievementState(identifier: "a", percentComplete: 70),
            GameCenterAchievementState(identifier: "a", percentComplete: 10)
        ]

        #expect(GameCenterController.updates(for: progress, existing: existing).isEmpty)
    }

    @Test("An achievement listed twice is reported once")
    func duplicateProgressIsReportedOnce() {
        let progress = [
            GameCenterAchievementProgress(identifier: "a", percentComplete: 40),
            GameCenterAchievementProgress(identifier: "a", percentComplete: 40)
        ]

        #expect(GameCenterController.updates(for: progress, existing: []).count == 1)
    }

    @Test("Exactly 100 percent shows the banner, 99.9 does not")
    func bannerBoundary() {
        let updates = GameCenterController.updates(
            for: [
                GameCenterAchievementProgress(identifier: "full", percentComplete: 100),
                GameCenterAchievementProgress(identifier: "almost", percentComplete: 99.9)
            ],
            existing: []
        )

        #expect(updates.first { $0.identifier == "full" }?.showsCompletionBanner == true)
        #expect(updates.first { $0.identifier == "almost" }?.showsCompletionBanner == false)
    }

    // MARK: - Errors and the reporting flag

    @Test("A failing load shows the error, reports nothing and ends the reporting state")
    func loadFailure() async {
        let service = RecordingService()
        service.loadError = ServiceFailure()
        let controller = controller(service)

        await controller.reportAchievements(from: summary(sessionCount: 1))

        #expect(controller.model.errorMessage == "Game Center is offline")
        #expect(!controller.model.isReportingAchievements)
        #expect(service.reports.isEmpty)
    }

    @Test("A failing report shows the error and ends the reporting state")
    func reportFailure() async {
        let service = RecordingService()
        service.reportError = ServiceFailure()
        let controller = controller(service)

        await controller.reportAchievements(from: summary(sessionCount: 1))

        #expect(controller.model.errorMessage == "Game Center is offline")
        #expect(!controller.model.isReportingAchievements)
    }

    @Test("A cancelled report is not shown as an error")
    func cancellationIsSilent() async {
        let service = RecordingService()
        service.loadError = CancellationError()
        let controller = controller(service)

        await controller.reportAchievements(from: summary(sessionCount: 1))

        #expect(controller.model.errorMessage == nil)
        #expect(!controller.model.isReportingAchievements)
    }

    @Test("A report that works clears an error of an earlier one")
    func successClearsTheError() async {
        let service = RecordingService()
        service.loadError = ServiceFailure()
        let controller = controller(service)
        await controller.reportAchievements(from: summary(sessionCount: 1))
        #expect(controller.model.errorMessage != nil)

        service.loadError = nil
        await controller.reportAchievements(from: summary(sessionCount: 1))

        #expect(controller.model.errorMessage == nil)
        #expect(service.reports.count == 1)
    }
}
#endif
