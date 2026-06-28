// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

struct StartAdventureGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Adventure Game"
    static let supportedModes: IntentModes = .foreground

    static var parameterSummary: some ParameterSummary {
        Summary("Start game for \(\.$target)")
    }

    @Parameter(title: "Adventure", requestValueDialog: "Which adventure to run?")
    var target: AdventureEntity

    @Dependency var root: AdventureRootModel
    @Dependency var navigator: Navigator

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        root.adventureGameControllable.startGame(with: target.id)
        root.startGame()
        navigator.perform(route: KnownRoutes.game)
        return .result(dialog: "Starting \"\(target.name)\".")
    }
}

#if os(iOS)
extension StartAdventureGameIntent: TargetContentProvidingIntent {}
#endif

#endif
