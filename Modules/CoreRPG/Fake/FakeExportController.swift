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
        get { _hubControllable! }
        set { _hubControllable = newValue }
    }

    @MainActor static let fake: FakeExportController = {
        FakeExportController(itemControllable: FakeItemController.fake)
    }()
}
