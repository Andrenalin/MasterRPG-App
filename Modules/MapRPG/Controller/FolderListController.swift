// @copyright André Trettin

import CoreRPG
import Foundation

/// This module's list destinations for the shared `GenericFolderListController`.
/// See CODE_AUDIT_Folder §9.4.
enum MapListRoutes: FolderListRouting {
    static func detail(for itemId: UUID) -> any NavigationDestination {
        MapRoute.detail(itemId)
    }

    static func folder(for itemId: UUID) -> any NavigationDestination {
        MapDetailRoute.folder(itemId)
    }

    static func folderInline(for itemId: UUID) -> any NavigationDestination {
        MapDetailRoute.folderInline(itemId)
    }

    static func viewer(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId)
    }
}

typealias FolderListController = GenericFolderListController<MapListRoutes>
