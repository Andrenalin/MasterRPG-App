// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AudioRPG

@MainActor
struct LinkControllerTests {
    @Test func toggleTextLink() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = await root.linkController
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: UUID(), entryId: nil, command: nil, in: "", shareResult: nil, toggler: nil, editAction: nil)
        #expect(result.isEmpty)
                
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: nil, toggler: nil, editAction: nil)
        var expectedText = "\(text)➡️[Play](RPG://AUDIOS/200/DEBCC881-3CA8-45C1-9406-14AD506E63BC/play) Rolling 2d20 sound for testing Audio⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.play.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.play.rawValue, in: result, shareResult: nil, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Play](RPG://AUDIOS/200/DEBCC881-3CA8-45C1-9406-14AD506E63BC/play)➡️playing⬅️ Rolling 2d20 sound for testing Audio⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.play.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.play.rawValue, in: result, shareResult: nil, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Play](RPG://AUDIOS/200/DEBCC881-3CA8-45C1-9406-14AD506E63BC/play)➡️playing⬅️ Rolling 2d20 sound for testing Audio⬅️"
        #expect(result == expectedText)
    }
}
