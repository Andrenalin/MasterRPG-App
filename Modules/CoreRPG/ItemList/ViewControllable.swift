// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

public enum GroupViewType: Hashable, Sendable {
    case none
    case item
    case photo
}

public protocol ViewControllable: Sendable {
    var goupViewType: GroupViewType { get }
}
