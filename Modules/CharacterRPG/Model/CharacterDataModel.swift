// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
public final class CharacterDataModel {
    public init(itemId: UUID = UUID(), photoId: UUID? = nil, photos: [UUID] = [], parentId: UUID? = nil) {
        self.itemId = itemId
        self.photoId = photoId
        self.photos = photos
        self.parentId = parentId
    }
    
    var itemId: UUID = UUID()
    var photoId: UUID? = nil
    var photos: [UUID] = []
    var parentId: UUID? = nil
}

extension CharacterDataModel {
    var entries: [CharacterEntryDataModel] {
        guard let modelContext else { return [] }
        let predicate = #Predicate<CharacterEntryDataModel> {
            $0.itemId == itemId
        }
        let fetch = FetchDescriptor<CharacterEntryDataModel>(predicate: predicate, sortBy: [SortDescriptor(\.index)])
        return (try? modelContext.fetch(fetch)) ?? []
    }
}

// MARK: - Conversion methods for Version2024 compatibility
extension CharacterDataModel {
    convenience init(_ model: CharacterModel) {
        self.init(
            itemId: model.id,
            photoId: model.photoId,
            photos: model.photos,
            parentId: model.parentId
        )
    }
    
    var characterModel: CharacterModel {
        CharacterModel(
            id: itemId,
            photoId: photoId,
            photos: photos,
            parentId: parentId,
            entries: entries.map { $0.characterEntryModel }
        )
    }
    
    func replace(_ model: CharacterModel) {
        photoId = model.photoId
        photos = model.photos
        parentId = model.parentId
        // Note: entries would need to be handled separately in a real implementation
    }
}
