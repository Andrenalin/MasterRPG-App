// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

public struct StartAdventureGameIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Adventure Game"
    public static let supportedModes: IntentModes = .foreground

    public static var parameterSummary: some ParameterSummary {
        Summary("Start game for \(\.$target)")
    }

    @Parameter(title: "Adventure", requestValueDialog: "Which adventure to run?")
    var target: AdventureEntity

    @Dependency var root: AdventureRootModel
    @Dependency var navigator: Navigator

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await DatabaseReadiness.wait()
        // `target` may have been deleted since it was cached. See CODE_AUDIT_21 §5.28.
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: "Which adventure to run?")
        await root.adventureGameControllable.startGame(with: target.id)
        root.startGame()
        navigator.perform(route: KnownRoutes.game)
        return .result(dialog: "Starting \"\(target.name)\".")
    }
}

#if os(iOS)
extension StartAdventureGameIntent: TargetContentProvidingIntent {}
#endif

#endif
