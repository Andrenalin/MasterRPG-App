// @copyright André Trettin

import Foundation
import SwiftUI

final class FakeExportController: ExportControllable, @unchecked Sendable {
    init(itemControllable: any ItemControllable, hubControllable: (any RootExportControllable)? = nil) {
        self.itemControllable = itemControllable
        self._hubControllable = hubControllable
    }

    var itemControllable: any ItemControllable
    private var _hubControllable: (any RootExportControllable)?
    var hubControllable: any RootExportControllable {
        get {
            guard let hub = _hubControllable else {
                preconditionFailure("\(itemControllable.config.module.token) export requires its Adventure export hub after setup.")
            }
            return hub
        }
        set { _hubControllable = newValue }
    }

    @MainActor static let fake: FakeExportController = {
        FakeExportController(itemControllable: FakeItemController.fake)
    }()
}
