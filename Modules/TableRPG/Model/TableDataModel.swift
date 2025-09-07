// @copyright André Trettin

import CodableModel
import CoreRPG
import Foundation
import SwiftData

@Model @CodableModel
public final class TableDataModel {
    public init(itemId: UUID = UUID(), diceId: UUID? = nil, entries: [TableEntryDataModel] = []) {
        self.itemId = itemId
        self.diceId = diceId
        self.entries = entries
    }
    
    var itemId: UUID = UUID()
    var diceId: UUID?
    
    @Relationship(deleteRule: .cascade) private var entries_: [TableEntryDataModel]? = []
}

extension TableDataModel {
    var entries: [TableEntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }
    
    subscript(id: UUID) -> TableEntryDataModel {
        get { entries.first(where: { $0.entryId == id }) ?? TableEntryDataModel(itemId: itemId) }
        set(newValue) {
            guard let index = entries.firstIndex(where: { $0.entryId == id }) else { return }
            entries[index] = newValue
        }
    }
}
