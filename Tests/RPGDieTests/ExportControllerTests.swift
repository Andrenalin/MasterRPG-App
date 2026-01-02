// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Testing

@testable import DiceRPG

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = await DiceRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        var ids = await sut.exportingAll()
        try #require(ids.ids[.dice] != nil)
        #expect(ids.ids[.dice]!.isEmpty)
        
        let itemId = await root.itemController.addNew(type: .item)
        ids = await sut.exportingAll()
        try #require(ids.ids[.dice] != nil)
        #expect(ids.ids[.dice]! == [itemId])
        
        let _ = await root.itemController.addNew(type: .item)
        ids = await sut.exportingAll()
        try #require(ids.ids[.dice] != nil)
        #expect(ids.ids[.dice]!.count == 2)
    }
    
    @Test func exporting() async throws {
        let root = await DiceRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .dice))
        var diceIds = ids.ids[.dice]
        try #require(diceIds != nil)
        #expect(diceIds!.count == 1)
        #expect(diceIds!.contains(itemId))
        #expect(!diceIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId, notConnected]), module: .dice))
        diceIds = ids.ids[.dice]
        try #require(diceIds != nil)
        #expect(diceIds!.count == 2)
        #expect(diceIds!.contains(itemId))
        #expect(!diceIds!.contains(newId))
        #expect(diceIds!.contains(notConnected))
    }
}
#endif
