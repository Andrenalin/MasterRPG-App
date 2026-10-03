// @copyright André Trettin

import CoreRPG
import Foundation

/// This module's list destinations for the shared `GenericFolderListController`.
/// See CODE_AUDIT_Folder §9.4.
enum PdfListRoutes: FolderListRouting {
    static func detail(for itemId: UUID) -> any NavigationDestination {
        PdfRoute.detail(itemId)
    }

    static func folder(for itemId: UUID) -> any NavigationDestination {
        PdfDetailRoute.folder(itemId)
    }

    static func folderInline(for itemId: UUID) -> any NavigationDestination {
        PdfDetailRoute.folderInline(itemId)
    }

    static func viewer(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId, nil)
    }
}

typealias FolderListController = GenericFolderListController<PdfListRoutes>
