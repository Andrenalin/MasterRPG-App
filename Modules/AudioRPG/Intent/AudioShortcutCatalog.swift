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

    @MainActor
    public static func reindexAll(root: AudioRootModel) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities = root.itemController.itemDataModel.items.compactMap { id -> AudioEntity? in
            guard let model = root.itemController.itemSync(for: id) else { return nil }
            return AudioEntity(root: root, model: model)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

public struct AudioFrameworkPackage: AppIntentsPackage { }

#endif
