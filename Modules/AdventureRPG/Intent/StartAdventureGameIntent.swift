// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

public struct StartAdventureGameIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Adventure Game"
    public static let description = IntentDescription(
        "Starts the game mode with an adventure, so players can join on their devices.",
        categoryName: "Game",
        searchKeywords: ["session", "play", "campaign", "game master"]
    )
    public static let supportedModes: IntentModes = .foreground

    public static var parameterSummary: some ParameterSummary {
        Summary("Start game for \(\.$target)")
    }

    @Parameter(title: "Adventure", requestValueDialog: .localized("Which adventure to run?", bundle: .module))
    public var target: AdventureEntity

    @Dependency var root: AdventureRootModel
    @Dependency var navigator: Navigator

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requireReadyDatabase()
        // `target` may have been deleted since it was cached. See CODE_AUDIT_21 §5.28.
        try requiredIntentTarget(root.itemController.itemSync(for: target.id), parameter: $target, prompt: .localized("Which adventure to run?", bundle: .module))
        await root.adventureGameControllable.startGame(with: target.id)
        root.startGame()
        navigator.perform(route: KnownRoutes.game)
        return .result(dialog: .localized("Starting \"\(target.name)\".", bundle: .module))
    }
}

#if os(iOS)
extension StartAdventureGameIntent: TargetContentProvidingIntent {}
#endif

extension AdventureRootModel {
    /// Donates the start of a game the user began from the UI, so Siri learns it next to the
    /// voice and Shortcuts path. Fire-and-forget, like `donateRoll` and `donatePlay`: the game
    /// start must not wait for the system. See CODE_AUDIT_AppIntents §4.4, CODE_AUDIT_Since_3.0.1 §3.5.
    @MainActor
    public func donateStartGame(of itemId: UUID) {
        guard let model = itemController.itemSync(for: itemId) else { return }
        let intent = StartAdventureGameIntent()
        intent.target = AdventureEntity(root: self, model: model)
        Task {
            await IntentDonations.donate(intent)
        }
    }
}

#endif
