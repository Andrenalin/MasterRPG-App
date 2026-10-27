// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CharacterRPG
import CoreRPG
import Foundation
import MapRPG

// MARK: - Battle round (game master)

/// Hands the turn to the next combatant of the running battle, as the Battle Round's "Next"
/// button does; the players get the change through the same broadcast. Only on the game master's
/// device. See CODE_AUDIT_AppIntents3 §4.8.
public struct NextTurnIntent: AppIntent {
    public static let title: LocalizedStringResource = "Next Turn"
    public static let description = IntentDescription(
        "Gives the turn to the next combatant of the running battle. Only the game master can do this.",
        categoryName: "Game",
        searchKeywords: ["battle", "combat", "initiative", "attacker"]
    )
    public static let supportedModes: IntentModes = .background

    @Dependency var root: GameRoot

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = root.battleRoundController.model
        guard model.isRunning else { return .result(dialog: GameIntentDialog.noBattle) }
        guard root.battleRoundController.nextAttacker() else { return .result(dialog: GameIntentDialog.masterOnly) }
        return .result(dialog: GameIntentDialog.turn(of: model))
    }
}

/// Starts the next round of the running battle. See CODE_AUDIT_AppIntents3 §4.8.
public struct NextRoundIntent: AppIntent {
    public static let title: LocalizedStringResource = "Next Round"
    public static let description = IntentDescription(
        "Starts the next round of the running battle. Only the game master can do this.",
        categoryName: "Game",
        searchKeywords: ["battle", "combat", "round", "initiative"]
    )
    public static let supportedModes: IntentModes = .background

    @Dependency var root: GameRoot

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = root.battleRoundController.model
        guard model.isRunning else { return .result(dialog: GameIntentDialog.noBattle) }
        guard root.battleRoundController.nextRound() else { return .result(dialog: GameIntentDialog.masterOnly) }
        let round = model.roundCounter
        if let name = model.activeEntry.flatMap({ model.attacker(for: $0) })?.name, !name.isEmpty {
            return .result(dialog: .localized(full: "Round \(round). \(name) has the turn.", supporting: "Round \(round)", bundle: .module))
        }
        return .result(dialog: .localized("Round \(round).", bundle: .module))
    }
}

/// Ends the running battle after a confirmation, as the Battle Round's End button does.
/// See CODE_AUDIT_AppIntents3 §4.8.
public struct EndBattleIntent: AppIntent {
    public static let title: LocalizedStringResource = "End Battle"
    public static let description = IntentDescription(
        "Ends the running battle. Only the game master can do this.",
        categoryName: "Game",
        searchKeywords: ["battle", "combat", "stop", "finish"]
    )
    public static let supportedModes: IntentModes = .background

    @Dependency var root: GameRoot

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard root.battleRoundController.model.isRunning else { return .result(dialog: GameIntentDialog.noBattle) }
        try await requestConfirmation(dialog: .localized("End the battle for everyone?", bundle: .module))
        guard root.battleRoundController.end() else { return .result(dialog: GameIntentDialog.masterOnly) }
        return .result(dialog: .localized("The battle has ended.", bundle: .module))
    }
}

// MARK: - Game session

/// Ends the game the game master runs, after a confirmation. A locked device cannot end a
/// session. See CODE_AUDIT_AppIntents3 §4.8, §6.
public struct StopGameIntent: AppIntent {
    public static let title: LocalizedStringResource = "Stop Game"
    public static let description = IntentDescription(
        "Ends the game you run as game master. The players are disconnected.",
        categoryName: "Game",
        searchKeywords: ["session", "end", "finish", "game master"]
    )
    public static let supportedModes: IntentModes = .background
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Dependency var root: GameRoot

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard root.gameModel.gameConfig.state == .started else {
            return .result(dialog: .localized("No game is running.", bundle: .module))
        }
        guard root.gameModel.gameConfig.isMaster else { return .result(dialog: GameIntentDialog.masterOnly) }
        try await requestConfirmation(dialog: .localized("End the game for all players?", bundle: .module))
        await root.stopGame()
        IntentGameContext.setGameState(false, .edit)
        return .result(dialog: .localized("The game has ended.", bundle: .module))
    }
}

/// Joins a game master's game on the local network with the code the master shows, as the
/// player's join screen does, with the character chosen there. The app comes to the front: a
/// game runs on screen. See CODE_AUDIT_AppIntents3 §4.8.
public struct JoinGameIntent: AppIntent {
    public static let title: LocalizedStringResource = "Join Game"
    public static let description = IntentDescription(
        "Joins a game on the local network with the code the game master shows, using the character chosen for playing.",
        categoryName: "Game",
        searchKeywords: ["session", "player", "connect", "code"]
    )
    public static let supportedModes: IntentModes = .foreground

    /// How long the intent looks for a game master on the local network.
    static let searchTimeout: Duration = .seconds(10)

    @Parameter(
        title: "Code",
        description: "The four-digit code the game master shows.",
        requestValueDialog: .localized("What is the game master's code?", bundle: .module)
    )
    var code: String

    @Dependency var root: GameRoot

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let joinCode = GameJoinCodeModel.sanitized(code)
        guard GameJoinCodeModel.isValidCode(joinCode) else {
            throw $code.needsValueError(.localized("The code has four digits. What is the game master's code?", bundle: .module))
        }
        guard root.gameModel.gameConfig.state != .started else {
            return .result(dialog: .localized("A game is already running.", bundle: .module))
        }
        guard root.characterRoot.linkControllable.validateLink(itemId: root.gameModel.selectedCharacter ?? UUID()) else {
            return .result(dialog: .localized("Choose your character on the game screen first.", bundle: .module))
        }
        guard let player = root.networkStore.model.playerStore else {
            return .result(dialog: .localized("Joining over the local network is not available on this device.", bundle: .module))
        }

        let browser = player.browserManager
        browser.screenAppeared()
        defer {
            // Discovery only runs while it is needed, as on the join screen. See CODE_AUDIT_Join §7.2.
            browser.screenDisappeared(keepRunning: player.networkModel.playerConnectionId != nil)
        }
        let masters = try await gameMasters(in: browser)
        guard !masters.isEmpty else {
            return .result(dialog: .localized("No game was found on the local network.", bundle: .module))
        }
        let target: BrowserGameModel
        if masters.count == 1 {
            target = masters[0]
        } else {
            let names = masters.map(\.deviceName)
            let chosen = try await $code.requestDisambiguation(
                among: names,
                dialog: .localized("Which game master do you want to join?", bundle: .module)
            )
            target = masters[names.firstIndex(of: chosen) ?? 0]
        }

        IntentGameContext.setGameState(false, .player)
        await root.startGame(to: target, mode: .player, supporterTier: IntentGameContext.supporterTier(), joinCode: joinCode)
        guard root.gameModel.gameConfig.state == .started else {
            IntentGameContext.setGameState(false, .edit)
            switch player.networkModel.joinFailure {
            case .badCode:
                throw $code.needsValueError(.localized("That code was not accepted. What is the game master's code?", bundle: .module))
            case .timedOut:
                return .result(dialog: .localized("The game master did not accept the connection in time.", bundle: .module))
            case .unreachable, nil:
                return .result(dialog: .localized("Couldn't reach the game master. Try again in a few seconds.", bundle: .module))
            }
        }
        IntentGameContext.setGameState(true, .player)
        root.gameJoinCodeModel.rememberMasterJoinCode(joinCode, forHost: target.endpointName)
        await MasterRPGTips.donateGameStartedOrJoined()
        return .result(dialog: .localized("Joined the game of \(target.deviceName).", bundle: .module))
    }

    /// The game masters the browser finds, waiting up to `searchTimeout` for the first.
    @MainActor
    private func gameMasters(in browser: BrowserManager) async throws -> [BrowserGameModel] {
        let deadline = ContinuousClock.now + Self.searchTimeout
        while true {
            let masters = browser.games.filter { $0.connectionMode == .observer }
            guard masters.isEmpty, ContinuousClock.now < deadline else { return masters }
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}

public extension GameRoot {
    /// The Control Center's Next Turn (`NextTurnControlIntent`); `false` without a battle or on a
    /// player's device.
    @discardableResult
    func nextTurn() -> Bool {
        battleRoundController.nextAttacker()
    }
}

// MARK: - Dialogs

enum GameIntentDialog {
    static var noBattle: IntentDialog {
        .localized("No battle is running.", bundle: .module)
    }

    static var masterOnly: IntentDialog {
        .localized("Only the game master can do that.", bundle: .module)
    }

    @MainActor
    static func turn(of model: BattleRoundModel) -> IntentDialog {
        guard let name = model.activeEntry.flatMap({ model.attacker(for: $0) })?.name, !name.isEmpty else {
            return .localized("Next turn.", bundle: .module)
        }
        return .localized(full: "\(name) has the turn.", supporting: "\(name)", bundle: .module)
    }
}

public struct GameFrameworkPackage: AppIntentsPackage { }

#endif
