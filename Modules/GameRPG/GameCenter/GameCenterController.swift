// @copyright André Trettin

import GameKit
import Observation
import SwiftUI

#if os(macOS)
import AppKit
typealias GameCenterPlatformViewController = NSViewController
#else
import UIKit
typealias GameCenterPlatformViewController = UIViewController
#endif

@MainActor
final class GameCenterAuthenticationRequest: Identifiable {
    let id = UUID()
    let viewController: GameCenterPlatformViewController

    init(viewController: GameCenterPlatformViewController) {
        self.viewController = viewController
    }
}

@MainActor @Observable
final class GameCenterModel: Sendable {
    private(set) var isAuthenticated = false
    private(set) var playerName = ""
    private(set) var errorMessage: String?
    private(set) var isReportingAchievements = false
    var authenticationRequest: GameCenterAuthenticationRequest?

    func updateAuthentication(player: GKLocalPlayer, error: Error?) {
        isAuthenticated = player.isAuthenticated
        playerName = player.isAuthenticated ? player.displayName : ""
        errorMessage = error?.localizedDescription
    }

    func requestAuthentication(with viewController: GameCenterPlatformViewController) {
        authenticationRequest = GameCenterAuthenticationRequest(viewController: viewController)
    }

    func dismissAuthentication() {
        authenticationRequest = nil
    }

    func beginReporting() {
        isReportingAchievements = true
    }

    func finishReporting(error: Error?) {
        isReportingAchievements = false
        errorMessage = error?.localizedDescription
    }
}

@MainActor
final class GameCenterController: Sendable {
    let model: GameCenterModel
    private let evaluator = GameCenterAchievementEvaluator()
    private var authenticationHandlerInstalled = false

    init(model: GameCenterModel) {
        self.model = model
    }

    func authenticate() {
        guard !authenticationHandlerInstalled else {
            model.updateAuthentication(player: .local, error: nil)
            return
        }
        authenticationHandlerInstalled = true

        GKLocalPlayer.local.authenticateHandler = { [weak model] viewController, error in
            Task { @MainActor in
                if let viewController {
                    model?.requestAuthentication(with: viewController)
                }
                model?.updateAuthentication(player: .local, error: error)
            }
        }
    }

    func reportAchievements(from summary: GameStatisticsSummary) async {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        model.beginReporting()
        do {
            let existing = try await GKAchievement.loadAchievements()
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.identifier, $0) })
            let progress = evaluator.progress(from: summary)
            var achievements: [GKAchievement] = []

            for item in progress where item.percentComplete > 0 {
                let achievement = existingByID[item.identifier] ?? GKAchievement(identifier: item.identifier)
                guard item.percentComplete > achievement.percentComplete else { continue }
                achievement.percentComplete = item.percentComplete
                achievement.showsCompletionBanner = item.percentComplete >= 100
                achievements.append(achievement)
            }

            if !achievements.isEmpty {
                try await GKAchievement.report(achievements)
            }
            model.finishReporting(error: nil)
        } catch is CancellationError {
            model.finishReporting(error: nil)
        } catch {
            model.finishReporting(error: error)
        }
    }

    func setAccessPoint(active: Bool) {
        GKAccessPoint.shared.location = .topLeading
        GKAccessPoint.shared.isActive = active && GKLocalPlayer.local.isAuthenticated
    }
}

struct GameCenterAchievementProgress: Hashable, Sendable {
    let identifier: String
    let percentComplete: Double
}

struct GameCenterAchievementEvaluator: Sendable {
    enum Identifier {
        static let firstGame = "de.andretrettin.masterrpg.achievement.first-game"
        static let regularAdventurer = "de.andretrettin.masterrpg.achievement.regular-adventurer"
        static let veteranAdventurer = "de.andretrettin.masterrpg.achievement.veteran-adventurer"
        static let storyteller = "de.andretrettin.masterrpg.achievement.storyteller"
        static let loyalHero = "de.andretrettin.masterrpg.achievement.loyal-hero"
        static let campaigner = "de.andretrettin.masterrpg.achievement.campaigner"
        static let wellTravelled = "de.andretrettin.masterrpg.achievement.well-travelled"
        static let diceInitiate = "de.andretrettin.masterrpg.achievement.dice-initiate"
        static let diceLegend = "de.andretrettin.masterrpg.achievement.dice-legend"
        static let criticalMoment = "de.andretrettin.masterrpg.achievement.critical-moment"
        static let unluckyHero = "de.andretrettin.masterrpg.achievement.unlucky-hero"
        static let multimediaMaestro = "de.andretrettin.masterrpg.achievement.multimedia-maestro"
        static let fullParty = "de.andretrettin.masterrpg.achievement.full-party"
        static let epicSession = "de.andretrettin.masterrpg.achievement.epic-session"
    }

    private enum DurationGoal {
        // Four hours is a typical game: ten GM games earn Storyteller,
        // twenty-five games with one character earn Loyal Hero, and eight hours is a long session.
        static let storyteller: TimeInterval = 40 * 3_600
        static let loyalHero: TimeInterval = 100 * 3_600
        static let epicSession: TimeInterval = 8 * 3_600
    }

    func progress(from summary: GameStatisticsSummary) -> [GameCenterAchievementProgress] {
        let longestCharacterDuration = summary.characters.map(\.value).max() ?? 0
        let longestAdventureCount = summary.adventures.map(\.count).max() ?? 0
        let sharedModuleCount = Set(summary.modules.filter { $0.count > 0 }.map(\.key)).count
        let largestParty = summary.recentSessions.map(\.maxParticipantCount).max() ?? 0

        return [
            progress(Identifier.firstGame, current: Double(summary.sessionCount), goal: 1),
            progress(Identifier.regularAdventurer, current: Double(summary.sessionCount), goal: 10),
            progress(Identifier.veteranAdventurer, current: Double(summary.sessionCount), goal: 50),
            progress(Identifier.storyteller, current: summary.gameMasterDuration, goal: DurationGoal.storyteller),
            progress(Identifier.loyalHero, current: longestCharacterDuration, goal: DurationGoal.loyalHero),
            progress(Identifier.campaigner, current: Double(longestAdventureCount), goal: 10),
            progress(Identifier.wellTravelled, current: Double(summary.adventures.count), goal: 5),
            progress(Identifier.diceInitiate, current: Double(summary.diceRollCount), goal: 100),
            progress(Identifier.diceLegend, current: Double(summary.diceRollCount), goal: 1_000),
            progress(Identifier.criticalMoment, current: Double(summary.criticalCount), goal: 1),
            progress(Identifier.unluckyHero, current: Double(summary.fumbleCount), goal: 1),
            progress(Identifier.multimediaMaestro, current: Double(sharedModuleCount), goal: 5),
            progress(Identifier.fullParty, current: Double(largestParty), goal: 5),
            progress(Identifier.epicSession, current: summary.longestDuration, goal: DurationGoal.epicSession)
        ]
    }

    private func progress(_ identifier: String, current: Double, goal: Double) -> GameCenterAchievementProgress {
        GameCenterAchievementProgress(
            identifier: identifier,
            percentComplete: min(100, max(0, current / goal * 100))
        )
    }
}

#if os(macOS)
struct GameCenterAuthenticationView: NSViewControllerRepresentable {
    let request: GameCenterAuthenticationRequest

    func makeNSViewController(context: Context) -> NSViewController {
        request.viewController
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
#else
struct GameCenterAuthenticationView: UIViewControllerRepresentable {
    let request: GameCenterAuthenticationRequest

    func makeUIViewController(context: Context) -> UIViewController {
        request.viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#endif
