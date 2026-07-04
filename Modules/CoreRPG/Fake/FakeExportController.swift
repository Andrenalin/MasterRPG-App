// @copyright André Trettin

import Foundation
import SwiftUI

final class FakeExportController: ExportControllable, @unchecked Sendable {
    init(itemControllable: any ItemControllable, rootController: (any RootControllable)? = nil) {
        self.itemControllable = itemControllable
        self._rootController = rootController
    }

    var itemControllable: any ItemControllable
    private var _rootController: (any RootControllable)?
    var rootController: any RootControllable {
        get { _rootController! }
        set { _rootController = newValue }
    }

    @MainActor static let fake: FakeExportController = {
        FakeExportController(itemControllable: FakeItemController.fake)
    }()
}
