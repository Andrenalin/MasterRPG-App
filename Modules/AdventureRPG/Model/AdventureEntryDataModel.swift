// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class AdventureEntryDataModel {
    public init(
        itemId: UUID = UUID(),
        entryId: UUID = UUID(),
        index: Int = 0,
        name: String = "",
        content: String = "",
        parent: AdventureDataModel? = nil
    ) {
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.content = content
        self.parent = parent
    }
    
    public var itemId: UUID = UUID()
    @Attribute(.preserveValueOnDeletion)
    public var entryId: UUID = UUID()
    public var index: Int = 0

    public var name: String = ""
    public var content: String = ""

    //@CodableIgnored
    var parent: AdventureDataModel? = nil
    
    // MARK: Codable
    
    struct AdventureEntryDataModelCodable: Equatable, Hashable, Codable, Sendable {
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
    
    convenience init(_ model: AdventureEntryDataModelCodable) {
        self.init(itemId: model.itemId, entryId: model.entryId, index: model.index, name: model.name, content: model.content)
    }
    
    var codableModel: AdventureEntryDataModelCodable {
        AdventureEntryDataModelCodable(
            itemId: itemId,
            entryId: entryId,
            index: index,
            name: name,
            content: content
        )
    }
    
    func replace(_ model: AdventureEntryDataModelCodable) {
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
}

extension AdventureEntryDataModel: EntryPersistentModel {
    public func duplicate(name: String, index: Int) -> AdventureEntryDataModel {
        AdventureEntryDataModel(
            itemId: itemId,
            entryId: UUID(),
            index: index,
            name: name,
            content: content,
            parent: parent
        )
    }
}
