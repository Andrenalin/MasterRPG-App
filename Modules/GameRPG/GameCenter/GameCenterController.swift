// @copyright André Trettin

import CoreRPG
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
        static let firstGame = "\(BundleIds.achievement).first_game"
        static let regularAdventurer = "\(BundleIds.achievement).regular_adventurer"
        static let veteranAdventurer = "\(BundleIds.achievement).veteran_adventurer"
        static let storyteller = "\(BundleIds.achievement).storyteller"
        static let loyalHero = "\(BundleIds.achievement).loyal_hero"
        static let campaigner = "\(BundleIds.achievement).campaigner"
        static let wellTravelled = "\(BundleIds.achievement).well_travelled"
        static let diceInitiate = "\(BundleIds.achievement).dice_initiate"
        static let diceLegend = "\(BundleIds.achievement).dice_legend"
        static let criticalMoment = "\(BundleIds.achievement).critical_moment"
        static let unluckyHero = "\(BundleIds.achievement).unlucky_hero"
        static let multimediaMaestro = "\(BundleIds.achievement).multimedia_maestro"
        static let fullParty = "\(BundleIds.achievement).full_party"
        static let epicSession = "\(BundleIds.achievement).epic_session"
        static let diceOverlord = "\(BundleIds.achievement).dice_overlord"
        static let fortunesFavorite = "\(BundleIds.achievement).fortunes_favorite"
        static let cursedDice = "\(BundleIds.achievement).cursed_dice"
        static let bothSides = "\(BundleIds.achievement).both_sides"
        static let hundredHourClub = "\(BundleIds.achievement).hundred_hour_club"
        static let grandCampaign = "\(BundleIds.achievement).grand_campaign"
    }

    private enum DurationGoal {
        // Four hours is a typical game: ten GM games earn Storyteller,
        // twenty-five games with one character earn Loyal Hero, and eight hours is a long session.
        static let storyteller: TimeInterval = 40 * 3_600
        static let loyalHero: TimeInterval = 100 * 3_600
        static let epicSession: TimeInterval = 8 * 3_600
        static let hundredHourClub: TimeInterval = 100 * 3_600
    }

    func progress(from summary: GameStatisticsSummary) -> [GameCenterAchievementProgress] {
        let longestCharacterDuration = summary.characters.map(\.value).max() ?? 0
        let longestAdventureCount = summary.adventures.map(\.count).max() ?? 0
        let sharedModuleCount = Set(summary.modules.filter { $0.count > 0 }.map(\.key)).count
        let largestParty = summary.recentSessions.map(\.maxParticipantCount).max() ?? 0
        // Each side of the screen is worth half: game master and player time.
        let rolesPlayed = (summary.gameMasterDuration > 0 ? 1.0 : 0) + (summary.playerDuration > 0 ? 1 : 0)

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
            progress(Identifier.epicSession, current: summary.longestDuration, goal: DurationGoal.epicSession),
            progress(Identifier.diceOverlord, current: Double(summary.diceRollCount), goal: 10_000),
            progress(Identifier.fortunesFavorite, current: Double(summary.criticalCount), goal: 100),
            progress(Identifier.cursedDice, current: Double(summary.fumbleCount), goal: 100),
            progress(Identifier.bothSides, current: rolesPlayed, goal: 2),
            progress(Identifier.hundredHourClub, current: summary.totalDuration, goal: DurationGoal.hundredHourClub),
            progress(Identifier.grandCampaign, current: Double(longestAdventureCount), goal: 25)
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
