// @copyright André Trettin

import SwiftUI

struct FakeImportController: ImportControllable {
    var itemControllable: any ItemControllable
    var editControllable: any EditControllable

    @MainActor
    static let fake = FakeImportController(itemControllable: FakeItemController.fake, editControllable: FakeEditController.fake)
}
