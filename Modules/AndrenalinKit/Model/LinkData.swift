// @copyright André Trettin

import SwiftUI

public struct LinkData: Codable, Transferable {
    public init(item: ItemRowTreeModel, name: String) {
        self.itemId = item.model.itemId
        self.entryId = item.model.entryId
        self.module = item.model.typeId
        self.name = name
    }

    public init(model: ItemRowModel, name: String) {
        self.itemId = model.itemId
        self.entryId = model.entryId
        self.module = model.typeId
        self.name = name
    }

    public init(itemId: UUID, entryId: UUID? = nil, module: NetworkModules, name: String) {
        self.itemId = itemId
        self.entryId = entryId
        self.module = module
        self.name = name
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: LinkData.self, contentType: .text)
        ProxyRepresentation(exporting: \.name)
    }

    public let itemId: UUID
    public let entryId: UUID?
    public let module: NetworkModules
    public let name: String
}
