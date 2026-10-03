// @copyright André Trettin

import Foundation

/// The four destinations a module's list opens. The only part of a list controller that
/// differs between modules.
@MainActor
public protocol FolderListRouting {
    static func detail(for itemId: UUID) -> any NavigationDestination
    static func folder(for itemId: UUID) -> any NavigationDestination
    static func folderInline(for itemId: UUID) -> any NavigationDestination
    static func viewer(for itemId: UUID) -> any NavigationDestination
}

/// The list controller every module shares; a module adopts it with its routes:
/// ```swift
/// typealias FolderListController = GenericFolderListController<PhotoListRoutes>
/// ```
/// Twelve modules carried a copy of this struct that differed only in the four route
/// expressions. See CODE_AUDIT_Folder §9.4.
@MainActor
public struct GenericFolderListController<Routes: FolderListRouting>: FolderListControllable {
    public init(
        listModel: FolderListModel,
        listDisplayModel: ListDisplayModel,
        itemControllable: any ItemControllable,
        searchRootControllable: any SearchRootControllable
    ) {
        self.listModel = listModel
        self.listDisplayModel = listDisplayModel
        self.itemControllable = itemControllable
        self.searchRootControllable = searchRootControllable
    }

    public let listModel: FolderListModel
    public let listDisplayModel: ListDisplayModel
    public let itemControllable: any ItemControllable
    public let searchRootControllable: any SearchRootControllable
    public let cacheListItemModel = CacheItemListModel()

    public func detailDestination(for itemId: UUID) -> any NavigationDestination {
        Routes.detail(for: itemId)
    }

    public func folderDestination(for itemId: UUID) -> any NavigationDestination {
        Routes.folder(for: itemId)
    }

    public func folderInlineDestination(for itemId: UUID) -> any NavigationDestination {
        Routes.folderInline(for: itemId)
    }

    public func viewerDestination(for itemId: UUID) -> any NavigationDestination {
        Routes.viewer(for: itemId)
    }
}
