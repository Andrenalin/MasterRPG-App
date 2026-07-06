// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import PdfRPG

@MainActor
struct LinkControllerTests {
    @Test func toggleTextLinkUsesItemAndEntryContent() async throws {
        let root = PdfRootModel.testRoot()
        let sut = root.linkController
        let itemId = UUID()
        let entryId = UUID()
        let entry = PdfEntryModel(id: entryId, name: "Chapter One", content: "Encounter rules", pageNumber: "12", bounds: .zero)
        let model = PdfModel(id: itemId, name: "Rule Notes", description: "Rules index", entries: [entry])
        root.itemController.replace(model: model, isInsert: true)

        let itemLink = sut.generateLink(linkNumber: 2, itemId: itemId, entryId: nil)
        #expect(itemLink.contains("[Rule Notes]"))
        #expect(itemLink.contains(itemId.uuidString))

        let entryLink = sut.generateLink(linkNumber: 3, itemId: itemId, entryId: entryId)
        #expect(entryLink.contains("[Chapter One]"))
        #expect(entryLink.contains(entryId.uuidString))

        let shareResult = ShareValueResult.preview()
        var itemText = sut.toggleTextLink(
            linkNumber: 2,
            itemId: itemId,
            entryId: nil,
            command: nil,
            in: itemLink,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(itemText.contains("[Share]"))
        #expect(itemText.contains("[Remove]"))
        #expect(itemText.contains("Rules index"))

        var entryText = sut.toggleTextLink(
            linkNumber: 3,
            itemId: itemId,
            entryId: entryId,
            command: nil,
            in: entryLink,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(entryText.contains("[Share]"))
        #expect(entryText.contains("[Show]"))
        #expect(entryText.contains("[Remove]"))
        #expect(entryText.contains("Encounter rules"))

        let ignoredCommand = sut.toggleTextLink(
            linkNumber: LinkType.share.linkNumberAddition + 2,
            itemId: itemId,
            entryId: nil,
            command: LinkType.share.rawValue,
            in: itemText,
            shareResult: nil,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(ignoredCommand == itemText)

        let shareText = sut.toggleTextLink(
            linkNumber: LinkType.share.linkNumberAddition + 2,
            itemId: itemId,
            entryId: nil,
            command: LinkType.share.rawValue,
            in: itemText,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(shareText == itemText)

        let showText = sut.toggleTextLink(
            linkNumber: LinkType.show.linkNumberAddition + 3,
            itemId: itemId,
            entryId: entryId,
            command: LinkType.show.rawValue,
            in: entryText,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(showText == entryText)

        itemText = sut.toggleTextLink(
            linkNumber: LinkType.remove.linkNumberAddition + 2,
            itemId: itemId,
            entryId: nil,
            command: LinkType.remove.rawValue,
            in: itemText,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(itemText == "Rule Notes")

        entryText = sut.toggleTextLink(
            linkNumber: LinkType.remove.linkNumberAddition + 3,
            itemId: itemId,
            entryId: entryId,
            command: LinkType.remove.rawValue,
            in: entryText,
            shareResult: shareResult,
            toggler: toggler(),
            editAction: editAction()
        )
        #expect(entryText == "Chapter One")

        try await Task.sleep(for: .milliseconds(1))
    }

    private func toggler() -> ((UUID, NetworkModules) async -> Void) {
        { _, _ in }
    }

    private func editAction() -> ((ItemRowModel) -> Bool) {
        { _ in true }
    }
}
