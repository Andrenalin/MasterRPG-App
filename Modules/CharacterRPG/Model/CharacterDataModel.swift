// @copyright André Trettin

import Foundation
import SwiftData

@Model 
public final class CharacterDataModel {
    public init(itemId: UUID = UUID(), diceId: UUID? = nil, photoId: UUID? = nil, photos: [UUID] = [], parentId: UUID? = nil, entries: [CharacterEntryDataModel] = []) {
        self.itemId = itemId
        self.diceId = diceId
        self.photoId = photoId
        self.photos = photos
        self.parentId = parentId
    }
    
    var itemId: UUID = UUID()
    var diceId: UUID? = nil
    var photoId: UUID? = nil
    var photos: [UUID] = []
    var parentId: UUID? = nil
    
    @Relationship(deleteRule: .cascade) private var entries_: [CharacterEntryDataModel]? = []
    
    // MARK: Codable
    
    struct CharacterDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), diceId: UUID? = nil, photoId: UUID? = nil, photos: [UUID] = [], parentId: UUID? = nil, entries: [CharacterEntryDataModel.CharacterEntryDataModelCodable] = []) {
            self.itemId = itemId
            self.diceId = diceId
            self.photoId = photoId
            self.photos = photos
            self.parentId = parentId
            self.entries = entries
        }
        var itemId: UUID = UUID()
        var diceId: UUID? = nil
        var photoId: UUID? = nil
        var photos: [UUID] = []
        var parentId: UUID? = nil
        var entries: [CharacterEntryDataModel.CharacterEntryDataModelCodable] = []
    }
    
    convenience init(_ model: CharacterDataModelCodable) {
        self.init(itemId: model.itemId, diceId: model.diceId, photoId: model.photoId, photos: model.photos, parentId: model.parentId, entries: [])
        self.entries = model.entries.map { CharacterEntryDataModel($0) }
    }
    
    var codableModel: CharacterDataModelCodable {
        CharacterDataModelCodable(
            itemId: itemId,
            diceId: diceId,
            photoId: photoId,
            photos: photos,
            parentId: parentId,
            entries: entries.map {
                $0.codableModel
            }
        )
    }
    
    func replace(_ model: CharacterDataModelCodable) {
        itemId = model.itemId
        diceId = model.diceId
        photoId = model.photoId
        photos = model.photos
        parentId = model.parentId
        entries = model.entries.map { CharacterEntryDataModel($0) }
    }
}

extension CharacterDataModel {
    var entries: [CharacterEntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }
}
