// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class AdventureDataModel {
    public init(itemId: UUID = UUID(), photoId: UUID? = nil, entries: [AdventureEntryDataModel] = []) {
        self.itemId = itemId
        self.displayState = 0
        
        self.photoId = photoId
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var itemId: UUID = UUID()
    public var displayState: Int = 0

    var photoId: UUID? = nil
    
    @Relationship(deleteRule: .cascade) private var entries_: [AdventureEntryDataModel]? = []
    
    // MARK: Codable
    
    struct AdventureDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), photoId: UUID? = nil, entries: [AdventureEntryDataModel.AdventureEntryDataModelCodable] = [], links: [LinkDataModel.Value] = []) {
            self.itemId = itemId
            self.photoId = photoId
            self.entries = entries
            self.links = links
        }
        var itemId: UUID = UUID()
        var photoId: UUID? = nil
        var entries: [AdventureEntryDataModel.AdventureEntryDataModelCodable] = []
        var links: [LinkDataModel.Value] = []
    }
    
    convenience init(_ model: AdventureDataModelCodable) {
        self.init(itemId: model.itemId, photoId: model.photoId, entries: [])
        self.entries = model.entries.map { AdventureEntryDataModel($0) }
    }
    
    @MainActor
    var codableModel: AdventureDataModelCodable {
        AdventureDataModelCodable(
            itemId: itemId,
            photoId: photoId,
            entries: entries.map {
                $0.codableModel
            },
            links: entries.flatMap {
                $0.links
            }
        )
    }
    
    func replace(_ model: AdventureDataModelCodable) {
        itemId = model.itemId
        photoId = model.photoId
        entries = model.entries.map { AdventureEntryDataModel($0) }
    }
    
    func duplicate(newItemId: UUID) -> AdventureDataModel {
        AdventureDataModel(
            itemId: newItemId,
            photoId: photoId,
            entries: entries.map { $0.duplicate(newItemId: newItemId, newEntryId: UUID()) }
        )
    }
}

extension AdventureDataModel {
    public var entries: [AdventureEntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }
    
    public subscript(id: UUID) -> AdventureEntryDataModel {
        get { entries.first(where: { $0.entryId == id }) ?? AdventureEntryDataModel(itemId: itemId) }
        set(newValue) {
            guard let index = entries.firstIndex(where: { $0.entryId == id }) else { return }
            entries[index] = newValue
        }
    }
}

extension AdventureDataModel: ModelCachable {
    public static func newModel(for itemId: UUID) -> AdventureDataModel {
        AdventureDataModel(itemId: itemId)
    }
}

extension AdventureDataModel: EntryEditModel {}
