// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController: EditControllable {
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController?
}
