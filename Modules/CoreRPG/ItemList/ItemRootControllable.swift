// @copyright André Trettin

import Foundation
import SwiftData

@MainActor
public protocol ItemRootControllable {
    var module: NetworkModules { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }

    var editControllable: any EditControllable { get }
    var itemControllable: any ItemControllable { get }
    var listControllable: any ListControllable { get }
}

@MainActor @Observable
public final class ItemRootController: ItemRootControllable {
    public init(module: NetworkModules, listDisplayModel: ListDisplayModel, searchModel: SearchModel, editControllable: any EditControllable, itemControllable: any ItemControllable, listControllable: any ListControllable) {
        self.module = module
        self.listDisplayModel = listDisplayModel
        self.searchModel = searchModel
        self.editControllable = editControllable
        self.itemControllable = itemControllable
        self.listControllable = listControllable
    }
    
    public let module: NetworkModules
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel

    public let editControllable: any EditControllable
    public let itemControllable: any ItemControllable
    public let listControllable: any ListControllable
}
