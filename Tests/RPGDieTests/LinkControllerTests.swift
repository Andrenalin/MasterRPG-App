// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGResourcesDebug
import Testing

@testable import DiceRPG

struct LinkControllerTests {
    @Test func toggleTextLink() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = root.linkController
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: UUID(), entryId: nil, command: nil, in: "", shareResult: nil, toggler: nil, editAction: nil)
        #expect(result.isEmpty)
        
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: nil, toggler: nil, editAction: nil)
        var expectedText = "\(text)➡️[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.roll.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.roll.rawValue, in: result, shareResult: nil, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)➡️"
        #expect(result.starts(with: expectedText))
        
        result = await sut.toggleTextLink(linkNumber: LinkType.roll.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.roll.rawValue, in: result, shareResult: nil, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)➡️"
        #expect(result.starts(with: expectedText))
    }
    
    @Test func toggleWithShare() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = root.linkController
        let shareResult: ShareValueResult = await ShareValueResult.preview()
        
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult, toggler: nil, editAction: nil)
        var expectedText = "\(text)➡️[Share](RPG://DICE/500/2201FBB7-0403-4A18-A361-CAD5A76A637D/share)[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.roll.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.roll.rawValue, in: result, shareResult: shareResult, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Share](RPG://DICE/500/2201FBB7-0403-4A18-A361-CAD5A76A637D/share)[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)➡️"
        #expect(result.starts(with: expectedText))
        
        result = await sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Share](RPG://DICE/500/2201FBB7-0403-4A18-A361-CAD5A76A637D/share)[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)➡️"
        #expect(result.starts(with: expectedText))
    }
    
    @Test func toggleWithShareAndToggler() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = root.linkController
        let shareResult: ShareValueResult = await ShareValueResult.preview()
                
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult, toggler: toggler(), editAction: nil)
        var expectedText = "\(text)➡️[Share](RPG://DICE/500/2201FBB7-0403-4A18-A361-CAD5A76A637D/share)[Show](RPG://DICE/600/2201FBB7-0403-4A18-A361-CAD5A76A637D/show)[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult, toggler: toggler(), editAction: nil)
        expectedText = "\(text)➡️[Share](RPG://DICE/500/2201FBB7-0403-4A18-A361-CAD5A76A637D/share)[Show](RPG://DICE/600/2201FBB7-0403-4A18-A361-CAD5A76A637D/show)[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)⬅️"
        #expect(result == expectedText)

        result = await sut.toggleTextLink(linkNumber: LinkType.roll.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.roll.rawValue, in: result, shareResult: shareResult, toggler: toggler(), editAction: nil)
        expectedText = "\(text)➡️[Share](RPG://DICE/500/2201FBB7-0403-4A18-A361-CAD5A76A637D/share)[Show](RPG://DICE/600/2201FBB7-0403-4A18-A361-CAD5A76A637D/show)[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)➡️"
        #expect(result.starts(with: expectedText))
    }

    @Test func toggleWithShareTogglerAndEditAction() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = root.linkController
        let shareResult: ShareValueResult = await ShareValueResult.preview()
                
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult, toggler: toggler(), editAction: editAction())
        var expectedText = "\(text)➡️[Share](RPG://DICE/500/2201FBB7-0403-4A18-A361-CAD5A76A637D/share)[Show](RPG://DICE/600/2201FBB7-0403-4A18-A361-CAD5A76A637D/show)[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)[Remove](RPG://DICE/300/2201FBB7-0403-4A18-A361-CAD5A76A637D/remove)⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult, toggler: toggler(), editAction: editAction())
        expectedText = "\(text)➡️[Share](RPG://DICE/500/2201FBB7-0403-4A18-A361-CAD5A76A637D/share)[Show](RPG://DICE/600/2201FBB7-0403-4A18-A361-CAD5A76A637D/show)[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)[Remove](RPG://DICE/300/2201FBB7-0403-4A18-A361-CAD5A76A637D/remove)⬅️"
        #expect(result == expectedText)

        result = await sut.toggleTextLink(linkNumber: LinkType.remove.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.remove.rawValue, in: result, shareResult: shareResult, toggler: toggler(), editAction: editAction())
        #expect(result == "CoC")
        
        result = await sut.toggleTextLink(linkNumber: LinkType.roll.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.roll.rawValue, in: expectedText, shareResult: shareResult, toggler: toggler(), editAction: nil)
        expectedText = "\(text)➡️[Share](RPG://DICE/500/2201FBB7-0403-4A18-A361-CAD5A76A637D/share)[Show](RPG://DICE/600/2201FBB7-0403-4A18-A361-CAD5A76A637D/show)[Roll](RPG://DICE/400/2201FBB7-0403-4A18-A361-CAD5A76A637D/roll)➡️"
        #expect(result.starts(with: expectedText))
    }

    @Test func handleDoubleLink() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController

        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let diceLink = await sut.generateLink(itemId: firstItem.id)

        let text = "**17**: \(diceLink)➡️[Roll](RPG://DICE/400/\(firstItem.id)/roll)➡️4 ∑4⬅️⬅️ KM"
        let result = await sut.handleTextLink(url: URL(string: "RPG://DICE/0/\(firstItem.id)")!, in: text, shareResult: nil, toggler: nil, editAction: nil)
        let exp = "**17**: \(diceLink) KM"
        #expect(result == exp)
    }
    
    private func toggler() -> ((UUID, NetworkModules) async -> Void) {
        { _, _ in }
    }
    
    private func editAction() -> ((ItemRowModel) -> Bool) {
        { _ in true }
    }
}
