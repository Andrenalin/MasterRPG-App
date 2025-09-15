// @copyright André Trettin

import Testing
import SwiftData
@testable import CoreRPG
@testable import DiceRPG
@testable import PdfRPG
@testable import TableRPG

struct TableRPGTests {

    @MainActor
    func makeRoot() throws -> TableRootModel {
        let modelContainer = try ModelContainer(for: ItemDataModel.self, LinkDataModel.self, TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let diceRoot = DiceRootModel(modelContext: modelContainer.mainContext)
        let pdfRoot = PdfRootModel(modelContext: modelContainer.mainContext)
        return TableRootModel(modelContext: modelContainer.mainContext, diceRoot: diceRoot, pdfRoot: pdfRoot)
    }
    
    @MainActor
    func models(in root: TableRootModel) -> [TableDataModel] {
        let ids = root.itemController.allItemIds()
        return ids.compactMap {
            root.itemController.model(for: $0)
        }
    }
    
    @MainActor @Test
    func copyTableAlsoCopiesDataAndEntries() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)
        
        let item = root.editControllable.addNew(modelContext: root.modelContext, module: .table, type: .item)
        
        let entry = TableEntryDataModel(itemId: item.id, index: 0, name: "Entry", content: "Value")
        let data = TableDataModel(itemId: item.id, diceId: nil, entries: [entry])
        root.modelContext.insert(entry)
        root.modelContext.insert(data)
        try? root.modelContext.save()
        
        root.editController.duplicate(item: item)
        let models = models(in: root)
        try #require(models.count == 2)
        let duplicat = models.first(where: { $0.itemId != item.id })
        try #require(duplicat != nil)
        
        guard let duplicat else { return }
        
        #expect(data.itemId != duplicat.itemId)
        try #require(data.entries.count == 1)
        try #require(duplicat.entries.count == 1)
        
        let originalEntry = data.entries[0]
        let copiedEntry = duplicat.entries[0]
        
        #expect(originalEntry.entryId != copiedEntry.entryId)
        #expect(originalEntry.name == copiedEntry.name)
        #expect(originalEntry.content == copiedEntry.content)
    }

}
