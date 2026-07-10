// @copyright André Trettin

import Foundation

public protocol FileControllable: Sendable {
    var fileUrlDataController: FileUrlDataController { get }
}
