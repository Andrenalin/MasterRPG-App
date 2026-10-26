// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum DiceShortcutCatalog {
    public static var all: [AppShortcut] {
        [
            open,
            create,
            addDie,
            rollSpecific,
            rollD20,
            rollD6,
            history,
            search,
            delete
        ]
    }

    public static var open: AppShortcut {
        AppShortcut(
            intent: OpenDiceIntent(),
            phrases: [
                "Open dice in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Dice",
            systemImageName: "dice"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateDiceIntent(),
            phrases: [
                "Create dice in \(.applicationName)"
            ],
            shortTitle: "Create Dice",
            systemImageName: "plus.circle"
        )
    }

    public static var addDie: AppShortcut {
        AppShortcut(
            intent: AddDieToDiceIntent(),
            phrases: [
                "Add a die to dice in \(.applicationName)"
            ],
            shortTitle: "Add Die",
            systemImageName: "die.face.6"
        )
    }

    public static var rollSpecific: AppShortcut {
        AppShortcut(
            intent: RollSpecificDiceIntent(),
            phrases: [
                "Roll my dice in \(.applicationName)",
                "Roll \(\.$dice) in \(.applicationName)"
            ],
            shortTitle: "Roll Dice",
            systemImageName: "dice"
        )
    }

    public static var rollD20: AppShortcut {
        AppShortcut(
            intent: RollDiceIntent(diceType: IntentDiceType.d20),
            phrases: [
                "Roll a D20 in \(.applicationName)",
                "Quick roll D20 in \(.applicationName)"
            ],
            shortTitle: "Roll D20",
            systemImageName: "dice.fill"
        )
    }

    public static var rollD6: AppShortcut {
        AppShortcut(
            intent: RollDiceIntent(diceType: IntentDiceType.d6),
            phrases: [
                "Roll a D6 in \(.applicationName)",
                "Quick roll D6 in \(.applicationName)"
            ],
            shortTitle: "Roll D6",
            systemImageName: "die.face.6.fill"
        )
    }

    public static var history: AppShortcut {
        AppShortcut(
            intent: ShowDiceHistoryIntent(),
            phrases: [
                "Show dice history in \(.applicationName)",
                "What was my last roll in \(.applicationName)"
            ],
            shortTitle: "Dice History",
            systemImageName: "clock.arrow.circlepath"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchDiceIntent(),
            phrases: [
                "Search dice in \(.applicationName)"
            ],
            shortTitle: "Search Dice",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteDiceIntent(),
            phrases: [
                "Delete dice in \(.applicationName)"
            ],
            shortTitle: "Delete Dice",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(DiceEntity.self, for: .dice)
    }

    @MainActor
    public static func reindexChanged(root: DiceRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .dice,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { DiceEntity(root: root, model: $0) }
        )
    }
}

public struct DiceFrameworkPackage: AppIntentsPackage { }

#endif
