// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum PhotoShortcutCatalog {
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
            intent: OpenPhotoIntent(),
            phrases: [
                "Open a photo in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Photo",
            systemImageName: "photo.on.rectangle.angled"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreatePhotoIntent(),
            phrases: [
                "Create a photo in \(.applicationName)"
            ],
            shortTitle: "Create Photo",
            systemImageName: "plus.circle"
        )
    }

    public static var addNote: AppShortcut {
        AppShortcut(
            intent: AddPhotoNoteIntent(),
            phrases: [
                "Add a note to a photo in \(.applicationName)"
            ],
            shortTitle: "Add Photo Note",
            systemImageName: "note.text.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchPhotosIntent(),
            phrases: [
                "Search photos in \(.applicationName)"
            ],
            shortTitle: "Search Photos",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeletePhotoIntent(),
            phrases: [
                "Delete a photo in \(.applicationName)"
            ],
            shortTitle: "Delete Photo",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(PhotoEntity.self, for: .photo)
    }

    @MainActor
    public static func reindexAll(root: PhotoRootModel) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities = root.itemController.itemDataModel.items.compactMap { id -> PhotoEntity? in
            guard let model = root.itemController.itemSync(for: id) else { return nil }
            return PhotoEntity(root: root, model: model)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

public struct PhotoFrameworkPackage: AppIntentsPackage { }

#endif
