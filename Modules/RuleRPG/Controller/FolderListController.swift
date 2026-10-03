// @copyright André Trettin

import CoreRPG
import Foundation

/// This module's list destinations for the shared `GenericFolderListController`.
/// See CODE_AUDIT_Folder §9.4.
enum RuleListRoutes: FolderListRouting {
    static func detail(for itemId: UUID) -> any NavigationDestination {
        RuleRoute.detail(itemId)
    }

    static func folder(for itemId: UUID) -> any NavigationDestination {
        RuleDetailRoute.folder(itemId)
    }

    static func folderInline(for itemId: UUID) -> any NavigationDestination {
        RuleDetailRoute.folderInline(itemId)
    }

    static func viewer(for itemId: UUID) -> any NavigationDestination {
        RuleViewerRoute.viewer(itemId)
    }
}

typealias FolderListController = GenericFolderListController<RuleListRoutes>
