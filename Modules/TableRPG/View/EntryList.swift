// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

import SwiftUI

struct EntryList: View {
    let itemId: UUID
    
    @Environment(TableRootModel.self) private var root
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        List {
            ForEach(entries) { entry in
                Text("\(entry.name): \(entry.content)")
            }
            .onDelete { indexSet in
                indexSet.forEach { index in
                    modelContext.delete(entries[index])
                }
            }
            .onMove { indexSet, index in
                var changedEntries = entries
                changedEntries.move(fromOffsets: indexSet, toOffset: index)
                
                changedEntries.enumerated().forEach { (index, element) in
                    element.index = index
                }
            }
        }
    }
    
    var model: TableDataModel? {
        root.itemController.model(for: itemId)
    }
    
    var entries: [TableEntryDataModel] {
        model?.entries ?? []
    }
}

#Preview(traits: .mockData) {
    EntryList(itemId: MockData.previewId)
}
