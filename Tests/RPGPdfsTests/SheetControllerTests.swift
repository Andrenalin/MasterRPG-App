// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import CoreGraphics
import Foundation
import Testing

@testable import PdfRPG

@MainActor
struct SheetControllerTests {
    @Test func pdfSheetBasic() async throws {
        let root = PdfRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let pdfModel = PdfModel(id: itemId, name: "Test PDF", description: "PDF Description")
        root.itemController.itemDataModel.itemData[itemId] = pdfModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: nil, level: 0, isShown: true)

        #expect(model.name == "Test PDF")
        #expect(model.description == "PDF Description")
        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.item)
        #expect(model.source.itemId == itemId)
        #expect(model.canAdd == false)
    }

    @Test func pdfSheetWithPhoto() async throws {
        let root = PdfRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let pdfModel = PdfModel(id: itemId, name: "Test", description: "")
        root.itemController.itemDataModel.itemData[itemId] = pdfModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: nil, level: 0, isShown: true)

        // First entry should be photo placeholder
        #expect(model.entries.count >= 1)
        #expect(model.entries.first?.sheetType == SheetModelType.photo)
    }

    @Test func pdfSheetEntries() async throws {
        let root = PdfRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let entry = PdfEntryModel(id: Foundation.UUID(), name: "Page 1", content: "Test content", pageNumber: "1", bounds: CGRect.zero)
        let pdfModel = PdfModel(id: itemId, name: "Test", description: "", entries: [entry])
        root.itemController.itemDataModel.itemData[itemId] = pdfModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: nil, level: 0, isShown: true)

        // Should have photo + entries
        #expect(model.entries.count >= 2)

        let pdfEntry = model.entries.first(where: { $0.name == "Page 1" })
        #expect(pdfEntry != nil)
        #expect(pdfEntry?.inlineEntries.count == 1)
        #expect(pdfEntry?.inlineEntries.first?.sheetType == SheetModelType.pdf)
    }

    @Test func pdfSheetWithDestination() async throws {
        let root = PdfRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let pdfModel = PdfModel(id: itemId, name: "Test", description: "")
        root.itemController.itemDataModel.itemData[itemId] = pdfModel

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.table)
        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: destination, level: 2, isShown: false)

        #expect(model.destination.itemId == destination.itemId)
        #expect(model.level == 2)
        #expect(model.isShown == false)
    }

    @Test func pdfSheetLevelLimit() async throws {
        let root = PdfRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let entry = PdfEntryModel(id: Foundation.UUID(), name: "Page 1", content: "Test", pageNumber: "1", bounds: CGRect.zero)
        let pdfModel = PdfModel(id: itemId, name: "Test", description: "", entries: [entry])
        root.itemController.itemDataModel.itemData[itemId] = pdfModel

        let entries = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId, level: 25)
        #expect(entries.isEmpty)

        let entriesBeforeLimit = sut.sheetEntries(root: RootManager(anyRoot: root), itemId: itemId, level: 24)
        #expect(entriesBeforeLimit.count > 0)
    }
}
#endif
