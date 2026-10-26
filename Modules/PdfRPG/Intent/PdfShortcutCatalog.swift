// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import Foundation

public enum PdfShortcutCatalog {
    public static var all: [AppShortcut] {
        [
            open,
            create,
            addBookmark,
            search,
            delete
        ]
    }

    public static var open: AppShortcut {
        AppShortcut(
            intent: OpenPdfIntent(),
            phrases: [
                "Open a PDF in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open PDF",
            systemImageName: "books.vertical"
        )
    }

    public static var create: AppShortcut {
        AppShortcut(
            intent: CreatePdfIntent(),
            phrases: [
                "Create a PDF in \(.applicationName)"
            ],
            shortTitle: "Create PDF",
            systemImageName: "plus.circle"
        )
    }

    public static var addBookmark: AppShortcut {
        AppShortcut(
            intent: AddPdfBookmarkIntent(),
            phrases: [
                "Add a bookmark to a PDF in \(.applicationName)"
            ],
            shortTitle: "Add PDF Bookmark",
            systemImageName: "doc.badge.plus"
        )
    }

    public static var search: AppShortcut {
        AppShortcut(
            intent: SearchPdfsIntent(),
            phrases: [
                "Search PDFs in \(.applicationName)"
            ],
            shortTitle: "Search PDFs",
            systemImageName: "magnifyingglass"
        )
    }

    public static var delete: AppShortcut {
        AppShortcut(
            intent: DeletePdfIntent(),
            phrases: [
                "Delete a PDF in \(.applicationName)"
            ],
            shortTitle: "Delete PDF",
            systemImageName: "trash"
        )
    }

    /// Names the entity type this module's donations use, so they can be deleted when an item is
    /// trashed or purged. See CODE_AUDIT_AppIntents §4.4.
    @MainActor
    public static func registerDonations() {
        IntentEntityIdentifiers.register(PdfEntity.self, for: .pdf)
    }

    @MainActor
    public static func reindexChanged(root: PdfRootModel) async {
        await reindexIntentEntities(
            itemDataModel: root.itemController.itemDataModel,
            module: .pdf,
            model: { root.itemController.itemSync(for: $0) },
            makeEntity: { PdfEntity(root: root, model: $0) }
        )
    }
}

public struct PdfFrameworkPackage: AppIntentsPackage { }

#endif
