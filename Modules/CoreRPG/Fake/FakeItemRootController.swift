// @copyright André Trettin

import Foundation
import SwiftData

public extension ItemRootController {
    @MainActor static let fake: ItemRootController = {
        var exportFake = FakeExportController.fake
        var linkFake = FakeLinkController.fake
        
        let root = ItemRootController(
            config: FakeModuleConfiguration(),
            navigationModel: ModuleNavigationModel(),
            inspectorEditorLinkModel: nil,
            openFileWindowModel: OpenFileWindowModel(),
            itemSelectionModel: ItemSelectionModel(),
            removeEntryListModel: RemoveEntryListModel(),
            cacheControllable: nil,
            editControllable: FakeEditController.fake,
            exportControllable: exportFake,
            gameControllable: FakeGameController.fake,
            importControllable: FakeImportController.fake,
            itemControllable: FakeItemController.fake,
            linkControllable: linkFake,
            folderListControllable: FakeFolderListController.fake,
            folderLinkControllable: FakeFolderListController.fake,
            searchControllable: FakeSearchController.fake,
            sheetControllable: FakeSheetController.fake,
            viewControllable: FakeViewController()
        )
        root.rootManager = RootManager.preview(fake: root)
        exportFake.rootController = FakeRootController.fake

        return root
    }()
}
