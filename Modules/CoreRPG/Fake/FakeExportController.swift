// @copyright André Trettin

import SwiftUI

final class FakeExportController: ExportControllable, @unchecked Sendable {
    init(itemControllable: any ItemControllable, _rootManager: RootManager? = nil, exportModel: ItemDataExportModel) {
        self.itemControllable = itemControllable
        self._rootManager = _rootManager
        self.exportModel = exportModel
    }
    
    var itemControllable: any ItemControllable
    var _rootManager: RootManager? = nil
    var exportModel: ItemDataExportModel
    
    var rootManager: RootManager { _rootManager! }
    
    @MainActor static let fake: FakeExportController = {
        var controller = FakeExportController(itemControllable: FakeItemController.fake, exportModel: ItemDataExportModel())
        return controller
    }()
}
