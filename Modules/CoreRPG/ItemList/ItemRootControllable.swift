// @copyright André Trettin

import Foundation
import SwiftData

@MainActor
public protocol ItemRootControllable {
    var module: NetworkModules { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }

    var editControllable: any OldEditControllable { get }
    var itemControllable: any ItemControllable { get }
    var listControllable: any ListControllable { get }
}
