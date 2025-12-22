// @copyright André Trettin

import Foundation
import SwiftData

@MainActor
public protocol ItemRootControllable: Sendable {
    var module: NetworkModules { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
    
    var currentSelectedItemId: UUID? { get }
    var itemSelectionModel: ItemSelectionModel { get }
    var removeEntryListModel: RemoveEntryListModel { get }

    var cacheControllable: (any ImageCacheControllable)? { get }
    var editControllable: any EditControllable { get }
    var exportControllable: any ExportControllable { get }
    var gameControllable: any GameControllable { get }
    var itemControllable: any ItemControllable { get }
    var linkControllable: any LinkControllable { get }
    var folderListControllable: any FolderListControllable { get }
    var folderLinkControllable: any FolderListControllable { get }
    var viewControllable: any ViewControllable { get }
    
    var rootController: ItemRootController { get }
}

@MainActor @Observable
public final class ItemRootController: ItemRootControllable {
    public init(
        module: NetworkModules,
        listDisplayModel: ListDisplayModel,
        searchModel: SearchModel,
        itemSelectionModel: ItemSelectionModel,
        removeEntryListModel: RemoveEntryListModel,
        cacheControllable: (any ImageCacheControllable)?,
        editControllable: any EditControllable,
        exportControllable: any ExportControllable,
        gameControllable: any GameControllable,
        itemControllable: any ItemControllable,
        linkControllable: any LinkControllable,
        folderListControllable: any FolderListControllable,
        viewControllable: any ViewControllable
    ) {
        self.module = module
        self.listDisplayModel = listDisplayModel
        self.searchModel = searchModel
        self.itemSelectionModel = itemSelectionModel
        self.removeEntryListModel = removeEntryListModel
        self.cacheControllable = cacheControllable
        self.editControllable = editControllable
        self.exportControllable = exportControllable
        self.gameControllable = gameControllable
        self.itemControllable = itemControllable
        self.linkControllable = linkControllable
        self.folderListControllable = folderListControllable
        self.folderLinkControllable = folderListControllable.copy(parentModel: nil)
        self.viewControllable = viewControllable
    }
    
    public let module: NetworkModules
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    public var itemSelectionModel: ItemSelectionModel
    public var currentSelectedItemId: UUID? {
        folderListControllable.listModel.selectedItemId
    }

    public let cacheControllable: (any ImageCacheControllable)?
    public let editControllable: any EditControllable
    public let exportControllable: any ExportControllable
    public let gameControllable: any GameControllable
    public let itemControllable: any ItemControllable
    public let linkControllable: any LinkControllable
    public let folderListControllable: any FolderListControllable
    public let folderLinkControllable: any FolderListControllable
    public let viewControllable: any ViewControllable
    
    public let removeEntryListModel: RemoveEntryListModel
    
    public var rootController: ItemRootController { self }
}
