// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
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

// MARK: - Conversion methods for Version2024 compatibility
extension TableDataModel {
    convenience init(_ model: TableModel) {
        self.init(
            itemId: model.id,
            diceId: model.diceId
        )
    }
    
    var tableModel: TableModel {
        TableModel(
            id: itemId,
            diceId: diceId,
            entries: entries.map { $0.tableEntryModel }
        )
    }
    
    func replace(_ model: TableModel) {
        diceId = model.diceId
        // Note: entries would need to be handled separately in a real implementation
    }
}
