// @copyright André Trettin

import Foundation
import SwiftData

@Model 
public final class AdventureDataModel {
    public init(itemId: UUID = UUID(), photoId: UUID? = nil, entries: [AdventureEntryDataModel] = []) {
        self.itemId = itemId
        self.photoId = photoId
    }
    
    var itemId: UUID = UUID()
    var photoId: UUID? = nil
    
    @Relationship(deleteRule: .cascade) private var entries_: [AdventureEntryDataModel]? = []
    
    // MARK: Codable
    
    struct AdventureDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), photoId: UUID? = nil, entries: [AdventureEntryDataModel.AdventureEntryDataModelCodable] = []) {
            self.itemId = itemId
            self.photoId = photoId
            self.entries = entries
        }
        var itemId: UUID = UUID()
        var photoId: UUID? = nil
        var entries: [AdventureEntryDataModel.AdventureEntryDataModelCodable] = []
    }
    
    convenience init(_ model: AdventureDataModelCodable) {
        self.init(itemId: model.itemId, photoId: model.photoId, entries: [])
        self.entries = model.entries.map { AdventureEntryDataModel($0) }
    }
    
    var codableModel: AdventureDataModelCodable {
        AdventureDataModelCodable(
            itemId: itemId,
            photoId: photoId,
            entries: entries.map {
                $0.codableModel
            }
        )
    }
    
    func replace(_ model: AdventureDataModelCodable) {
        itemId = model.itemId
        photoId = model.photoId
        entries = model.entries.map { AdventureEntryDataModel($0) }
    }
}

extension AdventureDataModel {
    var entries: [AdventureEntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }
    
    subscript(id: UUID) -> AdventureEntryDataModel {
        get { entries.first(where: { $0.entryId == id }) ?? AdventureEntryDataModel(itemId: itemId) }
        set(newValue) {
            guard let index = entries.firstIndex(where: { $0.entryId == id }) else { return }
            entries[index] = newValue
        }
    }
}
