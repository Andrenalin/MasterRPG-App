// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct LinkData: Codable, Transferable {
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
