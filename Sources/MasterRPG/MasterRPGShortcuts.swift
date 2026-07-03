// @copyright André Trettin

#if !os(tvOS)

import AdventureRPG
import AppIntents
import DiceRPG
import RolePlayGameKit

struct MasterRPGShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NavigateIntent(),
            phrases: [
                "Navigate around \(.applicationName)"
            ],
            shortTitle: "Navigate",
            systemImageName: "arrowshape.forward"
        )
        AppShortcut(
            intent: OpenAdventureIntent(),
            phrases: [
                "Open an adventure in \(.applicationName)"
            ],
            shortTitle: "Open Adventure",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: CreateAdventureIntent(),
            phrases: [
                "Create a new adventure in \(.applicationName)"
            ],
            shortTitle: "Create Adventure",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AppendAdventureSectionIntent(),
            phrases: [
                "Add a section to an adventure in \(.applicationName)"
            ],
            shortTitle: "Add Adventure Section",
            systemImageName: "doc.badge.plus"
        )
        AppShortcut(
            intent: StartAdventureGameIntent(),
            phrases: [
                "Start an adventure in \(.applicationName)"
            ],
            shortTitle: "Start Adventure Game",
            systemImageName: "gamecontroller"
        )
        AppShortcut(
            intent: SearchAdventuresIntent(),
            phrases: [
                "Search adventures in \(.applicationName)"
            ],
            shortTitle: "Search Adventures",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: DeleteAdventureIntent(),
            phrases: [
                "Delete an adventure in \(.applicationName)"
            ],
            shortTitle: "Delete Adventure",
            systemImageName: "trash"
        )
        AppShortcut(
            intent: RollSpecificDiceIntent(),
            phrases: [
                "Roll my dice in \(.applicationName)"
            ],
            shortTitle: "Roll Dice",
            systemImageName: "dice"
        )
        AppShortcut(
            intent: RollDiceIntent(diceType: .d20),
            phrases: [
                "Roll a D20 in \(.applicationName)"
            ],
            shortTitle: "Roll D20",
            systemImageName: "dice.fill"
        )
        AppShortcut(
            intent: RollDiceIntent(diceType: .d6),
            phrases: [
                "Roll a D6 in \(.applicationName)"
            ],
            shortTitle: "Roll D6",
            systemImageName: "die.face.6.fill"
        )
    }
}

#endif
