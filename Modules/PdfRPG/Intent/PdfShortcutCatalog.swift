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

    @MainActor
    public static func reindexAll(root: PdfRootModel) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let entities = root.itemController.itemDataModel.items.compactMap { id -> PdfEntity? in
            guard let model = root.itemController.itemSync(for: id) else { return nil }
            return PdfEntity(root: root, model: model)
        }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

public struct PdfFrameworkPackage: AppIntentsPackage { }

#endif
