// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation

struct AdventureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAdventureIntent(),
            phrases: [
                "Open in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
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
                "Start an adventure in \(.applicationName)",
                "Play \(\.$target) in \(.applicationName)"
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
    }
}

public struct AdventureFrameworkPackage: AppIntentsPackage { }

#endif
