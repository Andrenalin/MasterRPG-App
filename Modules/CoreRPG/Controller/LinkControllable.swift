// @copyright André Trettin

import Foundation
import SwiftUI

public protocol LinkControllable: Sendable {
    var module: NetworkModules { get }
    @MainActor var itemControllable: ItemControllable { get }

    @MainActor func toggleTextLink(model: LinkDataModel, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String
    @MainActor func validate(itemId: UUID, entryId: UUID?) -> Bool

    
    @MainActor func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel?
}

public extension LinkControllable {
    @MainActor func toggleTextLink(model: LinkDataModel, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        text
    }

    @MainActor func validate(itemId: UUID, entryId: UUID?) -> Bool {
        guard let item = itemControllable.modelSync(for: itemId) else { return false }
        return item.hasEntry(id: entryId)
    }
    


    @MainActor func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? { nil }
    func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] { [] }
    
    @MainActor func name(for id: UUID, entryId: UUID? = nil) -> String {
        guard let item = itemControllable.modelSync(for: id) else { return "" }
        if let entryId {
            return item[entryId].name
        }
        return item.name
    }
    
    @MainActor func specialLink(linkType: LinkType, model: LinkDataModel) -> String {
        let urlAdr = model.urlAdr
        return "[\(linkType.title)](\(urlAdr)/\(linkType.rawValue))"
    }
}
