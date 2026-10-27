// @copyright André Trettin

#if !os(tvOS)

import AdventureRPG
import AppIntents
import AudioRPG
import DiceRPG
import RolePlayGameKit

struct MasterRPGShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    /// Media the app does not have. Without these, "Play a movie in MasterRPG" is close enough to
    /// "Play <adventure>" and "Play audio" to start one of them. See CODE_AUDIT_AppIntents2 §4.7.
    static var negativePhrases: NegativeAppShortcutPhrases {
        NegativeAppShortcutPhrases(phrases: [
            "Play a movie in \(.applicationName)",
            "Play a video in \(.applicationName)",
            "Play a podcast in \(.applicationName)"
        ])
    }

    /// The 10 shortcuts the system allows, each with several wordings. Open and Start take an
    /// adventure by name. The rest of the intents are still in Shortcuts and found by Siri through
    /// the App Entity index, only without a fixed phrase. See CODE_AUDIT_AppIntents §5.6.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NavigateIntent(),
            phrases: [
                "Navigate around \(.applicationName)",
                "Go to a section of \(.applicationName)"
            ],
            shortTitle: "Navigate",
            systemImageName: "arrowshape.forward"
        )
        AppShortcut(
            intent: OpenAdventureIntent(),
            phrases: [
                "Open an adventure in \(.applicationName)",
                "Open \(\.$target) in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Adventure",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: StartAdventureGameIntent(),
            phrases: [
                "Start an adventure in \(.applicationName)",
                "Start \(\.$target) in \(.applicationName)",
                "Play \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Start Adventure Game",
            systemImageName: "gamecontroller"
        )
        AppShortcut(
            intent: CreateAdventureIntent(),
            phrases: [
                "Create a new adventure in \(.applicationName)",
                "Make a new adventure in \(.applicationName)"
            ],
            shortTitle: "Create Adventure",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: RollSpecificDiceIntent(),
            phrases: [
                "Roll my dice in \(.applicationName)",
                "Roll my dice set in \(.applicationName)"
            ],
            shortTitle: "Roll Dice",
            systemImageName: "dice"
        )
        AppShortcut(
            intent: RollDiceIntent(diceType: .d20),
            phrases: [
                "Roll a D20 in \(.applicationName)",
                "Roll a twenty sided die in \(.applicationName)"
            ],
            shortTitle: "Roll D20",
            systemImageName: "dice.fill"
        )
        AppShortcut(
            intent: RollDiceIntent(diceType: .d6),
            phrases: [
                "Roll a D6 in \(.applicationName)",
                "Roll a six sided die in \(.applicationName)"
            ],
            shortTitle: "Roll D6",
            systemImageName: "die.face.6.fill"
        )
        // A phrase cannot carry free text, so Siri asks which dice ("3d6 plus 2"). "Show Last Roll"
        // stays in Shortcuts and Siri without a fixed phrase. See CODE_AUDIT_AppIntents3 §4.6.
        AppShortcut(
            intent: RollDiceExpressionIntent(),
            phrases: [
                "Roll custom dice in \(.applicationName)",
                "Roll some dice in \(.applicationName)",
                "Make a dice roll in \(.applicationName)"
            ],
            shortTitle: "Roll Dice Expression",
            systemImageName: "dice"
        )
        AppShortcut(
            intent: PlayAudioIntent(),
            phrases: [
                "Play audio in \(.applicationName)",
                "Play music in \(.applicationName)"
            ],
            shortTitle: "Play Audio",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PauseAudioIntent(),
            phrases: [
                "Pause audio in \(.applicationName)",
                "Pause the music in \(.applicationName)"
            ],
            shortTitle: "Pause Audio",
            systemImageName: "pause.circle"
        )
    }
}

#endif
