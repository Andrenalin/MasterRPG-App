// @copyright André Trettin

import SwiftUI

struct FakeSearchController: SearchControllable {
    var itemControllable: any ItemControllable

    @MainActor
    static let fake = FakeSearchController(itemControllable: FakeItemController.fake)
}
