// @copyright André Trettin

import Foundation

struct FakeEditController: EditControllable {
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController?
}
