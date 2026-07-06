// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG

@MainActor
struct LinkControllerTests {
    @Test func toggleTextLinkAddsActionsAndRemovesLink() async throws {
        let root = PhotoRootModel.testRoot()
        let sut = root.linkController
        let itemId = UUID()
        let model = PhotoModel(id: itemId, name: "Sky Map", description: "Cloud city reference")
        root.itemController.replace(model: model, isInsert: true)

        let link = sut.generateLink(linkNumber: 7, itemId: itemId, entryId: nil)
        #expect(link.contains("[Sky Map]"))
        #expect(link.contains(itemId.uuidString))

        let entryLink = sut.generateLink(linkNumber: 8, itemId: itemId, entryId: UUID())
        #expect(entryLink.contains("RPG://PHOTOS/8/"))

        let shareResult = ShareValueResult.preview()
        var text = sut.toggleTextLink(
            linkNumber: 7,
            itemId: itemId,
            entryId: nil,
            command: nil,
            in: link,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )

        #expect(text.contains("[Share]"))
        #expect(text.contains("[Immersive]"))
        #expect(text.contains("[Show]"))
        #expect(text.contains("[Remove]"))
        #expect(text.contains("Cloud city reference"))

        let showText = sut.toggleTextLink(
            linkNumber: LinkType.show.linkNumberAddition + 7,
            itemId: itemId,
            entryId: nil,
            command: LinkType.show.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(showText == text)

        let shareText = sut.toggleTextLink(
            linkNumber: LinkType.share.linkNumberAddition + 7,
            itemId: itemId,
            entryId: nil,
            command: LinkType.share.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(shareText == text)

        let immersiveText = sut.toggleTextLink(
            linkNumber: LinkType.photoImmersive.linkNumberAddition + 7,
            itemId: itemId,
            entryId: nil,
            command: LinkType.photoImmersive.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(immersiveText == text)

        text = sut.toggleTextLink(
            linkNumber: LinkType.remove.linkNumberAddition + 7,
            itemId: itemId,
            entryId: nil,
            command: LinkType.remove.rawValue,
            in: text,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(text == "Sky Map")

        try await Task.sleep(for: .milliseconds(1))
    }

    private func toggler() -> ((UUID, NetworkModules) async -> Void) {
        { _, _ in }
    }

    private func editAction() -> ((ItemRowModel) -> Bool) {
        { _ in true }
    }
}
