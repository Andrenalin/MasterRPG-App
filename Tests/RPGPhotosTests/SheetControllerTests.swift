// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG

@MainActor
struct SheetControllerTests {
    @Test func photoSheetBasic() async throws {
        let root = PhotoRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let photoModel = PhotoModel(id: itemId, name: "Test Photo", description: "Description")
        root.itemController.itemDataModel.itemData[itemId] = photoModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: nil, level: 0, isShown: true)

        #expect(model.name == "Test Photo")
        #expect(model.description == "Description")
        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.photo)
        #expect(model.source.itemId == itemId)
        #expect(model.source.typeId == NetworkModules.photo)
    }

    @Test func photoSheetWithDestination() async throws {
        let root = PhotoRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let photoModel = PhotoModel(id: itemId, name: "Test", description: "")
        root.itemController.itemDataModel.itemData[itemId] = photoModel

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.value)
        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: destination, level: 1, isShown: false)

        #expect(model.destination.itemId == destination.itemId)
        #expect(model.level == 1)
        #expect(model.isShown == false)
    }

    @Test func photoSheetWithInlinePhoto() async throws {
        let root = PhotoRootModel.testRoot()

        let sut = SheetController(itemController: root.itemController)

        let itemId = Foundation.UUID()
        let photoModel = PhotoModel(id: itemId, name: "Test", description: "")
        root.itemController.itemDataModel.itemData[itemId] = photoModel

        let model = sut.sheet(root: RootManager(anyRoot: root), itemId: itemId, destination: nil, level: 0, isShown: true)

        // Photo sheet has inline photo entry
        #expect(model.inlineEntries.count == 1)
        #expect(model.inlineEntries.first?.sheetType == SheetModelType.photo)
        #expect(model.entries.isEmpty)
    }
}
#endif
