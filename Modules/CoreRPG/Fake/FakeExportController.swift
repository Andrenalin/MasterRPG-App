// @copyright André Trettin

import SwiftUI

struct FakeExportController: ExportControllable {
    var itemControllable: any ItemControllable
    var _rootManager: RootManager? = nil
    var exportModel: ItemDataExportModel
    
    var rootManager: RootManager { _rootManager! }

    
    @MainActor static let fake: FakeExportController = {
        var controller = FakeExportController(itemControllable: FakeItemController.fake, exportModel: ItemDataExportModel())
        controller._rootManager = RootManager.preview(fake: ItemRootController.fake)
        return controller
    }()
}
