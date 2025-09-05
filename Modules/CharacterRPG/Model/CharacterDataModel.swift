// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
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
