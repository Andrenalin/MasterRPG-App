// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class TableEntryDataModel {
    public init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "", parent: TableDataModel? = nil) {
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.content = content
    }
    
    public var itemId: UUID = UUID()
    public var entryId: UUID = UUID()
    public var index: Int = 0
    
    public var name: String = ""
    public var content: String = ""
    
    //@CodableIgnored
    var parent: TableDataModel? = nil
    
    // MARK: Codable
    
    struct TableEntryDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "") {
            self.itemId = itemId
            self.entryId = entryId
            self.index = index
            self.name = name
            self.content = content
        }
        var itemId: UUID = UUID()
        var entryId: UUID = UUID()
        var index: Int = 0
        var name: String = ""
        var content: String = ""
    }
    
    convenience init(_ model: TableEntryDataModelCodable) {
        self.init(itemId: model.itemId, entryId: model.entryId, index: model.index, name: model.name, content: model.content)
    }
    
    var codableModel: TableEntryDataModelCodable {
        TableEntryDataModelCodable(
            itemId: itemId,
            entryId: entryId,
            index: index,
            name: name,
            content: content
        )
    }
    
    func replace(_ model: TableEntryDataModelCodable) {
        itemId = model.itemId
        entryId = model.entryId
        index = model.index
        name = model.name
        content = model.content
    }

    @MainActor
    var links: [LinkDataModel.LinkDataModelCodable] {
        guard let modelContext else { return [] }
        let linkRegisterController = LinkRegisterController(container: modelContext.container)
        return linkRegisterController.linkDataModel(in: content).map { $0.codableModel }
    }

    func duplicate(newItemId: UUID, newEntryId: UUID) -> TableEntryDataModel {
        TableEntryDataModel(
            itemId: newItemId,
            entryId: newEntryId,
            index: index,
            name: name,
            content: content,
            parent: nil
        )
    }
}

extension TableEntryDataModel: EntryPersistentModel {
    public func duplicate(name: String, index: Int) -> TableEntryDataModel {
        TableEntryDataModel(itemId: itemId, entryId: UUID(), index: index, name: name, content: content, parent: parent)
    }
}
