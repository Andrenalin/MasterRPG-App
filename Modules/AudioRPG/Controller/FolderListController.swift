// @copyright André Trettin

import CoreRPG
import Foundation

/// This module's list destinations for the shared `GenericFolderListController`.
/// See CODE_AUDIT_Folder §9.4.
enum AudioListRoutes: FolderListRouting {
    static func detail(for itemId: UUID) -> any NavigationDestination {
        AudioRoute.detail(itemId)
    }

    static func folder(for itemId: UUID) -> any NavigationDestination {
        AudioDetailRoute.folder(itemId)
    }

    static func folderInline(for itemId: UUID) -> any NavigationDestination {
        AudioDetailRoute.folderInline(itemId)
    }

    static func viewer(for itemId: UUID) -> any NavigationDestination {
        AudioRoute.detail(itemId)
    }
}

typealias FolderListController = GenericFolderListController<AudioListRoutes>
