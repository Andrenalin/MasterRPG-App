// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import RPGTables
import RPGResourcesDebug
import Testing

@testable import RPGValues

struct LinkControllerTests {
    @Test func createGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController

        let itemId = await root.itemController.addNew(type: nil).itemId
        let item = await root.itemController.item(for: itemId)?.copy()
        #expect(nil != item)
        let entryId = UUID()
        item!.entries.append(ValueEntryModel(id: entryId, name: "Some Value", type: .number, isGenerator: false, value: "27", diceId: nil, valueId: nil))
        await root.itemController.replace(model: item!, isInsert: false, shouldRepairLinks: true)

        var result = "**Some Value**: 27 "
        await #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entryId: entryId) == result)

        item![entryId].value = "27+2"
        await root.itemController.replace(model: item!, isInsert: false, shouldRepairLinks: true)

        result = "**Some Value**: 27+2 = 29"
        await #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entryId: entryId) == result)

        item![entryId].value = "27+2+3"
        await root.itemController.replace(model: item!, isInsert: false, shouldRepairLinks: true)

        result = "**Some Value**: 27+2+3 = 32"
        await #expect(sut.linkText(model: root.itemController.itemOrEmpty(for: itemId), entryId: entryId) == result)
    }
    
    @Test func toggleWithShareTogglerAndEditAction() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = root.linkController
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult(), toggler: toggler(), editAction: editAction())
        var expectedText = "\(text)➡️[Share](RPG://VALUES/500/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/share)[Show](RPG://VALUES/600/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/show) Adalbert Unheil / Timo’s Character / 11 Entries [Remove](RPG://VALUES/300/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/remove)⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult(), toggler: toggler(), editAction: editAction())
        expectedText = "\(text)➡️[Share](RPG://VALUES/500/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/share)[Show](RPG://VALUES/600/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/show) Adalbert Unheil / Timo’s Character / 11 Entries [Remove](RPG://VALUES/300/E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358/remove)⬅️"
        #expect(result == expectedText)

        result = await sut.toggleTextLink(linkNumber: LinkType.remove.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.remove.rawValue, in: result, shareResult: shareResult(), toggler: toggler(), editAction: editAction())
        #expect(result == "Adalbert Unheil")
    }
    
    @MainActor
    private func shareResult() -> ShareValueResult {
        ShareValueResult.preview()
    }
    
    private func toggler() -> ((UUID, NetworkModules) async -> Void) {
        { _, _ in }
    }
    
    private func editAction() -> ((ItemRowModel) -> Bool) {
        { _ in true }
    }
}
#endif
