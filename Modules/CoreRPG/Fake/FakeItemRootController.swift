// @copyright André Trettin

import Foundation
import SwiftData

public extension ItemRootController {
    @MainActor static let fake = ItemRootController(
        module: .adventure,
        config: FakeModuleConfiguration(),
        listDisplayModel: ListDisplayModel(),
        searchModel: SearchModel.preview(),
        itemSelectionModel: ItemSelectionModel(),
        removeEntryListModel: RemoveEntryListModel(),
        cacheControllable: nil,
        editControllable: FakeEditController.fake,
        exportControllable: FakeExportController.fake,
        gameControllable: FakeGameController.fake,
        itemControllable: FakeItemController.fake,
        linkControllable: FakeLinkController.fake,
        folderListControllable: FakeFolderListController.fake,
        viewControllable: FakeViewController()
    )
}
