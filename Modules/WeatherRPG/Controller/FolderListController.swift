// @copyright André Trettin

import CoreRPG
import Foundation

/// This module's list destinations for the shared `GenericFolderListController`.
/// See CODE_AUDIT_Folder §9.4.
enum WeatherListRoutes: FolderListRouting {
    static func detail(for itemId: UUID) -> any NavigationDestination {
        WeatherRoute.detail(itemId)
    }

    static func folder(for itemId: UUID) -> any NavigationDestination {
        WeatherDetailRoute.folder(itemId)
    }

    static func folderInline(for itemId: UUID) -> any NavigationDestination {
        WeatherDetailRoute.folderInline(itemId)
    }

    static func viewer(for itemId: UUID) -> any NavigationDestination {
        DetailRoute.viewer(itemId)
    }
}

typealias FolderListController = GenericFolderListController<WeatherListRoutes>
