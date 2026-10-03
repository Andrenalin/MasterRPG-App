// @copyright André Trettin

import CoreRPG
import Foundation

/// This module's list destinations for the shared `GenericFolderListController`.
/// See CODE_AUDIT_Folder §9.4.
enum DiceListRoutes: FolderListRouting {
    static func detail(for itemId: UUID) -> any NavigationDestination {
        DiceRoute.detail(itemId)
    }

    static func folder(for itemId: UUID) -> any NavigationDestination {
        DiceDetailRoute.folder(itemId)
    }

    static func folderInline(for itemId: UUID) -> any NavigationDestination {
        DiceDetailRoute.folderInline(itemId)
    }

    static func viewer(for itemId: UUID) -> any NavigationDestination {
        DiceRoute.detail(itemId)
    }
}

typealias FolderListController = GenericFolderListController<DiceListRoutes>
