// @copyright André Trettin

import Foundation
import SwiftData

@Model
public final class TableDataModel {
    public init(id: UUID = UUID(), diceId: UUID? = nil) {
        self.id = id
        self.diceId = diceId
    }
    
    public var id: UUID = UUID()
    var diceId: UUID?
}

extension TableDataModel {
    var entries: [TableEntryDataModel] {
        guard let modelContext else { return [] }
        let predicate = #Predicate<TableEntryDataModel> {
            $0.parentId == id
        }
        let fetch = FetchDescriptor<TableEntryDataModel>(predicate: predicate, sortBy: [SortDescriptor(\.index)])
        return (try? modelContext.fetch(fetch)) ?? []
    }
}
