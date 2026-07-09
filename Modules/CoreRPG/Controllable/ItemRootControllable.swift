// @copyright André Trettin

import Foundation
import SwiftData

@MainActor
public protocol ItemRootControllable: Sendable {
    var rootManager: RootManager? { get }
    var configurable: ModuleConfigurable { get }
    var navigationModel: ModuleNavigationModel { get }
    var inspectorEditorLinkModel: EditorLinkModel? { get }
    var openFileWindowModel: OpenFileWindowModel { get }

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

public extension ItemRootControllable {
    var searchModel: SearchModel { folderListControllable.searchModel }
    var rootManager: RootManager? { rootController.rootManager }
}

@MainActor @Observable
public final class ItemRootController: ItemRootControllable {
    public init(
        rootManager: RootManager? = nil,
        config: ModuleConfigurable,
        navigationModel: ModuleNavigationModel,
        inspectorEditorLinkModel: EditorLinkModel?,
        openFileWindowModel: OpenFileWindowModel,
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
        folderLinkControllable: any FolderListControllable,
        searchControllable: any SearchControllable,
        sheetControllable: any SheetControllable,
        viewControllable: any ViewControllable
    ) {
        self.rootManager = rootManager
        self.configurable = config
        self.navigationModel = navigationModel
        self.inspectorEditorLinkModel = inspectorEditorLinkModel
        self.openFileWindowModel = openFileWindowModel
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
        self.folderLinkControllable = folderLinkControllable
        self.searchControllable = searchControllable
        self.sheetControllable = sheetControllable
        self.viewControllable = viewControllable
    }

    @ObservationIgnored public var rootManager: RootManager?
    public let configurable: ModuleConfigurable
    public let navigationModel: ModuleNavigationModel
    public let inspectorEditorLinkModel: EditorLinkModel?
    public let openFileWindowModel: OpenFileWindowModel

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
