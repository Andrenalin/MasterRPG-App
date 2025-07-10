// @copyright André Trettin

import Foundation

public protocol FileControllable: FileUrlAccessible {
    var fileUrlDataController: FileUrlDataController { get }
}
