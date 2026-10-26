// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum AudioShortcutCatalog {
    public static var all: [AppShortcut] {
        [
            open,
            create,
            addNote,
            play,
            pause,
            search,
            delete
        ]
    }

    public static var open: AppShortcut {
        AppShortcut(
            intent: OpenAudioIntent(),
            phrases: [
                "Open audio in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Audio",
            systemImageName: "music.note.list"
        )
    }

    public static var play: AppShortcut {
        AppShortcut(
            intent: PlayAudioIntent(),
            phrases: [
                "Play audio in \(.applicationName)",
                "Play \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Play Audio",
            systemImageName: "play.circle"
        )
    }

    public static var pause: AppShortcut {
        AppShortcut(
            intent: PauseAudioIntent(),
            phrases: [
                "Pause audio in \(.applicationName)"
            ],
            shortTitle: "Pause Audio",
            systemImageName: "pause.circle"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreateAudioIntent(),
            phrases: [
                "Create audio in \(.applicationName)"
            ],
            shortTitle: "Create Audio",
            systemImageName: "plus.circle"
        )
    }

    public static var addNote: AppShortcut {
        AppShortcut(
            intent: AddAudioNoteIntent(),
            phrases: [
                "Add a note to audio in \(.applicationName)"
            ],
            shortTitle: "Add Audio Note",
            systemImageName: "note.text.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchAudioIntent(),
            phrases: [
                "Search audio in \(.applicationName)"
            ],
            shortTitle: "Search Audio",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeleteAudioIntent(),
            phrases: [
                "Delete audio in \(.applicationName)"
            ],
            shortTitle: "Delete Audio",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(AudioEntity.self, for: .audio)
    }

    @MainActor
    public static func reindexAll(root: AudioRootModel) async {
        await reindexIntentEntities(
            ids: root.itemController.itemDataModel.items,
            module: .audio,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { AudioEntity(root: root, model: $0) }
        )
    }
}

public struct AudioFrameworkPackage: AppIntentsPackage { }

#endif
