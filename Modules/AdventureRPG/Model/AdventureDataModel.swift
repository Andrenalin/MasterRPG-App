// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
public final class AdventureDataModel {
    public init(itemId: UUID = UUID(), photoId: UUID? = nil, entries: [AdventureEntryDataModel] = []) {
        self.itemId = itemId
        self.photoId = photoId
    }
    
    var itemId: UUID = UUID()
    var photoId: UUID? = nil
    
    @Relationship(deleteRule: .cascade) private var entries_: [AdventureEntryDataModel]? = []
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
}
