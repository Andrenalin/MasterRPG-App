// @copyright André Trettin

import Foundation

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
    var generationControllable: (any ItemGenerationControllable)? { get }

    var rootController: ItemRootController { get }

    // The database maintenance every module root shares. Requirements, not only the defaults
    // below: a root that overrides one (Character repairs its own data in `checkFolders`) is
    // reached by a call through `any ItemRootControllable` too. See CODE_AUDIT §9.5.
    func checkFolders(reportModel: ValidateRepairModel) async
    func validateLinks(reportModel: ValidateRepairModel) async
    func itemDataCleanup() async
}

public extension ItemRootControllable {
    /// The live game view's persistent sheet slot (`ItemEditorModel.gameSheetRootModel`): the
    /// stored instance moved to `itemId`, or a new one stored for the next selection and
    /// reappearance. It mutates observable state, so a view calls it from `onChange`, never from
    /// `body`. `isGameEditor: true`: edits made in the game persist like the editor's. Cleared by
    /// the module's `GameController.resetGameState()` when the game ends. `nil` while the root has
    /// no root manager. See CODE_AUDIT_28 §8.1.
    @MainActor func resolveGameSheetRootModel(for itemId: UUID) -> SheetRootModel? {
        if let existing = editControllable.editorModel.gameSheetRootModel {
            existing.reset(itemId: itemId)
            return existing
        }
        guard let rootManager else { return nil }
        let created = SheetRootModel(
            rootManager: rootManager,
            linkControllable: linkControllable,
            sheetControllable: sheetControllable,
            itemId: itemId,
            isEditor: false,
            isGameEditor: true
        )
        editControllable.editorModel.gameSheetRootModel = created
        return created
    }

    var searchModel: SearchModel { folderListControllable.searchModel }
    var rootManager: RootManager? { rootController.rootManager }
    var generationControllable: (any ItemGenerationControllable)? {
        rootController.generationControllable
    }
}

/// The database maintenance every module root shares: repairing folders and hidden items,
/// validating links and removing orphaned items. A module overrides `checkFolders` only when it
/// has data of its own to repair (Character). See CODE_AUDIT_Audio2 §9.11.
@MainActor
public extension ItemRootControllable {
    /// Deletes the items that are hidden everywhere (`totalHidden`) and so reachable by nobody.
    func itemDataCleanup() async {
        for itemId in itemControllable.itemDataModel.items {
            guard let model = await itemControllable.item(for: itemId) else { continue }
            if model.isHidden {
                await editControllable.delete(itemId: model.id)
            }
        }
    }

    func checkFolders(reportModel: ValidateRepairModel) async {
        let controller = ConvertController(itemController: itemControllable, editController: editControllable)
        await controller.repairHiddenAndFolders(reportModel: reportModel)
    }

    func validateLinks(reportModel: ValidateRepairModel) async {
        await linkControllable.validateLinks(reportModel: reportModel)
    }
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
        viewControllable: any ViewControllable,
        generationControllable: (any ItemGenerationControllable)? = nil
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
        self.generationControllable = generationControllable
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
    public let generationControllable: (any ItemGenerationControllable)?

    public let removeEntryListModel: RemoveEntryListModel

    public var rootController: ItemRootController { self }
}
