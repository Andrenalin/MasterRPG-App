// @copyright André Trettin

import Foundation
import SwiftData

public extension ItemRootController {
    @MainActor static let fake: ItemRootController = {
        var exportFake = FakeExportController.fake
        var linkFake = FakeLinkController.fake
        
        let root = ItemRootController(
            config: FakeModuleConfiguration(),
            listDisplayModel: ListDisplayModel(),
            searchModel: SearchModel.preview(),
            navigationModel: ModuleNavigationModel(),
            inspectorEditorLinkModel: nil,
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
            searchControllable: FakeSearchController.fake,
            viewControllable: FakeViewController()
        )
        exportFake._rootManager = RootManager.preview(fake: root)
        linkFake._rootManager = RootManager.preview(fake: root)
        
        return root
    }()
}
