// @copyright André Trettin

import Foundation
import SwiftData

public struct ItemDataCodableModel: Codable, Hashable, Equatable, Sendable {
    public init(
        id: UUID,
        module: NetworkModules,
        name: CRDT<String>,
        information: CRDT<String>,
        category: ItemListCategory,
        tags: [String] = [],
        fileUrl: FileUrl?,
        displayState: Int,
        parentId: UUID?,
        entries: [EntryDataCodableModel],
        externalData: Data?
    ) {
        self.id = id
        self.module = module

        self.name = name
        self.information = information

        self.category = category
        self.tags = tags
        self.fileUrl = fileUrl

        self.displayState = displayState
        self.parentId = parentId

        self.entries = entries

        self.externalData = externalData
    }
    
    public var id: UUID
    public var module: NetworkModules

    public var name: CRDT<String>
    public var information: CRDT<String>

    public var category: ItemListCategory
    public var tags: [String]
    public var fileUrl: FileUrl?

    public var displayState: Int
    public var parentId: UUID?

    public var entries: [EntryDataCodableModel]

    public var externalData: Data?
}
