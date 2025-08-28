// @copyright André Trettin

import Foundation
import SwiftData

@MainActor
public protocol ItemRootControllable {
    var module: NetworkModules { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
    
    var currentSelectedItemId: UUID? { get }
    var singleSelectionModel: SingleSelectionModel { get }
    var multiSelectionModel: MultiSelectionModel { get}

    var cacheControllable: (any ImageCacheControllable)? { get }
    var editControllable: any EditControllable { get }
    var itemControllable: any ItemControllable { get }
    var listControllable: any ListControllable { get }
    var listLinkControllable: any ListControllable { get }
    var viewControllable: any ViewControllable { get }
}

@MainActor @Observable
public final class ItemRootController: ItemRootControllable {
    public init(module: NetworkModules, listDisplayModel: ListDisplayModel, searchModel: SearchModel, singleSelectionModel: SingleSelectionModel, multiSelectionModel: MultiSelectionModel, cacheControllable: (any ImageCacheControllable)?, editControllable: any EditControllable, itemControllable: any ItemControllable, listControllable: any ListControllable, listLinkControllable: any ListControllable, viewControllable: any ViewControllable) {
        self.module = module
        self.listDisplayModel = listDisplayModel
        self.searchModel = searchModel
        self.singleSelectionModel = singleSelectionModel
        self.multiSelectionModel = multiSelectionModel
        self.cacheControllable = cacheControllable
        self.editControllable = editControllable
        self.itemControllable = itemControllable
        self.listControllable = listControllable
        self.listLinkControllable = listLinkControllable
        self.viewControllable = viewControllable
    }
    
    public let module: NetworkModules
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    public var singleSelectionModel: SingleSelectionModel
    public var multiSelectionModel: MultiSelectionModel
    public var currentSelectedItemId: UUID? {
        listControllable.listModel(for: nil).selectedItemId
    }

    public let cacheControllable: (any ImageCacheControllable)?
    public let editControllable: any EditControllable
    public let itemControllable: any ItemControllable
    public let listControllable: any ListControllable
    public let listLinkControllable: any ListControllable
    public let viewControllable: any ViewControllable
}
