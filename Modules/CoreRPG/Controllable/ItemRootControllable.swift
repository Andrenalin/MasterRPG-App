// @copyright André Trettin

import Foundation
import SwiftData

@MainActor
public protocol ItemRootControllable: Sendable {
    var configurable: ModuleConfigurable { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
    var navigationModel: ModuleNavigationModel { get }
    var inspectorEditorLinkModel: EditorLinkModel? { get }
    
    var currentSelectedItemId: UUID? { get }
    var itemSelectionModel: ItemSelectionModel { get }
    var removeEntryListModel: RemoveEntryListModel { get }

    var cacheControllable: (any ImageCacheControllable)? { get }
    var editControllable: any EditControllable { get }
    var exportControllable: any ExportControllable { get }
    var gameControllable: any GameControllable { get }
    var importControllable: any ImportControllable { get }
    var itemControllable: any ItemControllable { get }
    var linkControllable: any LinkControllable { get }
    var folderListControllable: any FolderListControllable { get }
    var folderLinkControllable: any FolderListControllable { get }
    var searchControllable: any SearchControllable { get }
    var sheetControllable: any SheetControllable { get }
    var viewControllable: any ViewControllable { get }
    
    var rootController: ItemRootController { get }
}

@MainActor @Observable
public final class ItemRootController: ItemRootControllable {
    public init(
        config: ModuleConfigurable,
        listDisplayModel: ListDisplayModel,
        searchModel: SearchModel,
        navigationModel: ModuleNavigationModel,
        inspectorEditorLinkModel: EditorLinkModel?,
        itemSelectionModel: ItemSelectionModel,
        removeEntryListModel: RemoveEntryListModel,
        cacheControllable: (any ImageCacheControllable)?,
        editControllable: any EditControllable,
        exportControllable: any ExportControllable,
        gameControllable: any GameControllable,
        importControllable: any ImportControllable,
        itemControllable: any ItemControllable,
        linkControllable: any LinkControllable,
        folderListControllable: any FolderListControllable,
        searchControllable: any SearchControllable,
        sheetControllable: any SheetControllable,
        viewControllable: any ViewControllable
    ) {
        self.configurable = config
        self.listDisplayModel = listDisplayModel
        self.searchModel = searchModel
        self.navigationModel = navigationModel
        self.inspectorEditorLinkModel = inspectorEditorLinkModel
        self.itemSelectionModel = itemSelectionModel
        self.removeEntryListModel = removeEntryListModel
        self.cacheControllable = cacheControllable
        self.editControllable = editControllable
        self.exportControllable = exportControllable
        self.gameControllable = gameControllable
        self.importControllable = importControllable
        self.itemControllable = itemControllable
        self.linkControllable = linkControllable
        self.folderListControllable = folderListControllable
        self.folderLinkControllable = folderListControllable.copy(parentModel: nil)
        self.searchControllable = searchControllable
        self.sheetControllable = sheetControllable
        self.viewControllable = viewControllable
    }
    
    public let configurable: ModuleConfigurable
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public let navigationModel: ModuleNavigationModel
    public let inspectorEditorLinkModel: EditorLinkModel?
    
    public var itemSelectionModel: ItemSelectionModel
    public var currentSelectedItemId: UUID? {
        folderListControllable.listModel.selectedItemId
    }

    public let cacheControllable: (any ImageCacheControllable)?
    public let editControllable: any EditControllable
    public let exportControllable: any ExportControllable
    public let gameControllable: any GameControllable
    public let importControllable: any ImportControllable
    public let itemControllable: any ItemControllable
    public let linkControllable: any LinkControllable
    public let folderListControllable: any FolderListControllable
    public let folderLinkControllable: any FolderListControllable
    public let searchControllable: any SearchControllable
    public let sheetControllable: any SheetControllable
    public let viewControllable: any ViewControllable
    
    public let removeEntryListModel: RemoveEntryListModel
    
    public var rootController: ItemRootController { self }
}
