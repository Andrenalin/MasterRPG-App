// @copyright André Trettin

import Foundation
import SwiftData

@Model
public final class TableDataModel {
    public init(itemId: UUID = UUID(), diceId: UUID? = nil) {
        self.itemId = itemId
        self.diceId = diceId
    }
    
    var itemId: UUID = UUID()
    var diceId: UUID?
}

extension TableDataModel {
    var entries: [TableEntryDataModel] {
        guard let modelContext else { return [] }
        let predicate = #Predicate<TableEntryDataModel> {
            $0.itemId == itemId
        }
        let fetch = FetchDescriptor<TableEntryDataModel>(predicate: predicate, sortBy: [SortDescriptor(\.index)])
        return (try? modelContext.fetch(fetch)) ?? []
    }
}
