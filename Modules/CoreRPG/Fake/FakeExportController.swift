// @copyright André Trettin

import Foundation
import SwiftUI

final class FakeExportController: ExportControllable, @unchecked Sendable {
    init(itemControllable: any ItemControllable, _rootManager: RootManager? = nil) {
        self.itemControllable = itemControllable
        self._rootManager = _rootManager
    }

    var itemControllable: any ItemControllable
    var _rootManager: RootManager? = nil

    var rootManager: RootManager { _rootManager! }

    @MainActor static let fake: FakeExportController = {
        FakeExportController(itemControllable: FakeItemController.fake)
    }()
}
