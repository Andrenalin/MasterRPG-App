// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

struct LinkControllerTests {
    @Test func generateLinks() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController

        let itemId = await root.itemControllable.itemDataModel.items[0]

        let link = await sut.generateLink(linkNumber: 3, itemId: itemId, entryId: nil)
        #expect(link == "[3D Item](RPG://SPACES/3/B76C7CA1-D594-4123-9563-33545ADD23A3)")

        let entryId = UUID()
        let linkWithEntry = await sut.generateLink(linkNumber: 3, itemId: itemId, entryId: entryId)
        #expect(linkWithEntry == "[](RPG://SPACES/3/\(entryId))")
    }

    @Test func toggleWithShareTogglerAndEditAction() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = root.linkController
        let shareResult: ShareValueResult = await ShareValueResult.preview()
                
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult, toggler: toggler(), editAction: editAction())
        var expectedText = "\(text)➡️[Share](RPG://SPACES/500/B76C7CA1-D594-4123-9563-33545ADD23A3/share)[Show](RPG://SPACES/600/B76C7CA1-D594-4123-9563-33545ADD23A3/show)[Remove](RPG://SPACES/300/B76C7CA1-D594-4123-9563-33545ADD23A3/remove)⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult, toggler: toggler(), editAction: editAction())
        expectedText = "\(text)➡️[Share](RPG://SPACES/500/B76C7CA1-D594-4123-9563-33545ADD23A3/share)[Show](RPG://SPACES/600/B76C7CA1-D594-4123-9563-33545ADD23A3/show)[Remove](RPG://SPACES/300/B76C7CA1-D594-4123-9563-33545ADD23A3/remove)⬅️"
        #expect(result == expectedText)

        result = await sut.toggleTextLink(linkNumber: LinkType.remove.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.remove.rawValue, in: result, shareResult: shareResult, toggler: toggler(), editAction: editAction())
        #expect(result == "3D Item")
    }

    private func toggler() -> ((UUID, NetworkModules) async -> Void) {
        { _, _ in }
    }
    
    private func editAction() -> ((ItemRowModel) -> Bool) {
        { _ in true }
    }
}
