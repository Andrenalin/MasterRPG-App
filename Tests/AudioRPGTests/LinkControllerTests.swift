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
        
        let sut = root.linkController
        var result = sut.toggleTextLink(linkNumber: 0, itemId: UUID(), entryId: nil, command: nil, in: "", shareResult: nil, toggler: nil, editAction: nil)
        #expect(result.isEmpty)
                
        let firstItem = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = sut.generateLink(itemId: firstItem.id)
        result = sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: nil, toggler: nil, editAction: nil)
        var expectedText = "\(text)➡️[Play](RPG://AUDIOS/200/DEBCC881-3CA8-45C1-9406-14AD506E63BC/play) Rolling 2d20 sound for testing Audio⬅️"
        #expect(result == expectedText)
        
        result = sut.toggleTextLink(linkNumber: LinkType.play.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.play.rawValue, in: result, shareResult: nil, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Play](RPG://AUDIOS/200/DEBCC881-3CA8-45C1-9406-14AD506E63BC/play)➡️playing⬅️ Rolling 2d20 sound for testing Audio⬅️"
        #expect(result == expectedText)
        
        result = sut.toggleTextLink(linkNumber: LinkType.play.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.play.rawValue, in: result, shareResult: nil, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Play](RPG://AUDIOS/200/DEBCC881-3CA8-45C1-9406-14AD506E63BC/play)➡️playing⬅️ Rolling 2d20 sound for testing Audio⬅️"
        #expect(result == expectedText)
    }

    @Test func toggleTextLinkAddsShareShowAndRemoveActions() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.linkController
        let shareResult = ShareValueResult.preview()
        let firstItem = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let link = sut.generateLink(itemId: firstItem.id)

        var text = sut.toggleTextLink(
            linkNumber: 0,
            itemId: firstItem.id,
            entryId: nil,
            command: nil,
            in: link,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )

        #expect(text.contains("[Share]"))
        #expect(text.contains("[Show]"))
        #expect(text.contains("[Play]"))
        #expect(text.contains("[Remove]"))
        #expect(text.contains(firstItem.description))

        let showText = sut.toggleTextLink(
            linkNumber: LinkType.show.linkNumberAddition,
            itemId: firstItem.id,
            entryId: nil,
            command: LinkType.show.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(showText == text)

        let shareText = sut.toggleTextLink(
            linkNumber: LinkType.share.linkNumberAddition,
            itemId: firstItem.id,
            entryId: nil,
            command: LinkType.share.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(shareText == text)

        text = sut.toggleTextLink(
            linkNumber: LinkType.remove.linkNumberAddition,
            itemId: firstItem.id,
            entryId: nil,
            command: LinkType.remove.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(text == firstItem.name)

        try await Task.sleep(for: .milliseconds(1))
    }

    private func toggler() -> ((UUID, NetworkModules) async -> Void) {
        { _, _ in }
    }

    private func editAction() -> ((ItemRowModel) -> Bool) {
        { _ in true }
    }
}
