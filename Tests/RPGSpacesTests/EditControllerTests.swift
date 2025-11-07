// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGResourcesDebug
import Testing

@testable import RPGSpaces

struct EditControllerTests {
    @Test func resetName() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalName = item.name
        #expect(originalName == "3D Item")

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newName = "Updated Item Name"
        await sut.reset(name: newName)

        #expect(await sut.model.name == newName)
        #expect(item.name == newName)
    }

    @Test func resetNameWithWhitespace() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newName = "  Trimmed Name  "
        await sut.reset(name: newName)

        #expect(await sut.model.name == "Trimmed Name")
        #expect(item.name == "Trimmed Name")
    }

    @Test func resetCategory() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalCategory = item.category
        #expect(originalCategory == .item)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newCategory = ItemListCategory.building
        await sut.reset(category: newCategory)

        #expect(await sut.model.category == newCategory)
        #expect(item.category == newCategory)
    }

    @Test func resetCategoryNoChangeWhenSame() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalCategory = item.category

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Reset to the same category should not trigger changes
        await sut.reset(category: originalCategory)

        #expect(await sut.model.category == originalCategory)
        #expect(item.category == originalCategory)
    }

    @Test func resetFileUrl() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        let newFileUrl = FileUrl(fileId: UUID(), url: URL(fileURLWithPath: "/test/path"), location: .local, module: "TEST", relativeUrl: nil)
        await sut.reset(fileUrl: newFileUrl, for: item.id)

        #expect(await sut.model.fileUrl == newFileUrl)
        #expect(item.fileUrl == newFileUrl)
    }

    @Test func resetFileUrlForDifferentItem() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Create a new item
        let newItem = await root.itemController.addNew(type: nil)
        let targetItem = await root.itemController.itemOrEmpty(for: newItem.itemId)

        let newFileUrl = FileUrl(fileId: UUID(), url: URL(fileURLWithPath: "/test/path2"), location: .local, module: "TEST", relativeUrl: nil)
        await sut.reset(fileUrl: newFileUrl, for: targetItem.id)

        // The current model should remain unchanged
        #expect(await sut.model.id == item.id)
        #expect(await sut.model.fileUrl != newFileUrl)

        // The target item should have the new fileUrl
        let updatedTargetItem = await root.itemController.itemOrEmpty(for: targetItem.id)
        #expect(updatedTargetItem.fileUrl == newFileUrl)
    }

    @Test func resetSpaceWithNilUrl() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Reset space with nil URL should remove the file URL
        sut.resetSpace(url: nil)

        #expect(await sut.model.fileUrl == nil)
        #expect(item.fileUrl == nil)
    }

    @Test func resetNameNoChangeWhenSame() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let originalName = item.name

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .space))

        // Reset to the same name should not trigger changes
        await sut.reset(name: originalName)

        #expect(await sut.model.name == originalName)
        #expect(item.name == originalName)
    }
}
