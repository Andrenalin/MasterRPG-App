// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

struct EditController: EditControllable {
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController?
}
