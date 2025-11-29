// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import PdfRPG
import CoreGraphics

struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = await PdfRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.exportController

        var ids = await sut.exportingAll()
        try #require(ids.ids[.pdf] != nil)
        #expect(ids.ids[.pdf]!.isEmpty)

        let itemId = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exportingAll()
        try #require(ids.ids[.pdf] != nil)
        #expect(ids.ids[.pdf]! == [itemId])

        let _ = await root.itemController.addNew(type: nil).itemId
        let entry = PdfEntryModel(id: UUID(), name: "Hello", content: "Mega", pageNumber: "2", bounds: .zero)
        await root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = await sut.exportingAll()
        try #require(ids.ids[.pdf] != nil)
        #expect(ids.ids[.pdf]!.count == 2)
    }


    @Test func exporting() async throws {
        let root = await PdfRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: nil).itemId

        let newId = await root.itemController.addNew(type: nil).itemId
        let _ = PdfEntryModel(id: UUID(), name: "Hello", content: "Mega", pageNumber: "2", bounds: .zero)
        var ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .pdf))
        var pdfIds = ids.ids[.pdf]
        try #require(pdfIds != nil)
        #expect(pdfIds!.count == 1)
        #expect(pdfIds!.contains(itemId))
        #expect(!pdfIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: nil).itemId
        ids = await sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId, notConnected]), module: .pdf))
        pdfIds = ids.ids[.pdf]
        try #require(pdfIds != nil)
        #expect(pdfIds!.count == 2)
        #expect(pdfIds!.contains(itemId))
        #expect(!pdfIds!.contains(newId))
        #expect(pdfIds!.contains(notConnected))
    }
}
#endif
