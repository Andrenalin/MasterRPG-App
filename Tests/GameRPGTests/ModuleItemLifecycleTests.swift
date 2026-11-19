// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT_TestGaps §5.12: the item lifecycle every module shares (`ItemControllable`), run
/// once for each module root of one in-memory app instead of through a test file per module:
/// add an item or a folder, add several, delete one and keep the others, delete what does not
/// exist, and find it in the folder structure. The module-specific overrides are tested in the
/// module's own target.
@MainActor
@Suite("Module item lifecycle")
struct ModuleItemLifecycleTests {
    /// Every module with an item list. (Generator holds no user items.)
    nonisolated static let modules: [NetworkModules] = [
        .adventure, .audio, .dice, .map, .pdf, .photo, .rule, .space, .table, .value, .weather
    ]

    private func itemController(for module: NetworkModules) throws -> any ItemControllable {
        let app = AppModel.preview
        let root = try #require(app.root.itemRootController(for: module), "no root for \(module)")
        return root.itemControllable
    }

    @Test("A new item is added to the list, with its own id", arguments: modules)
    func addItem(module: NetworkModules) async throws {
        let controller = try itemController(for: module)
        let before = controller.itemDataModel.items

        let itemId = await controller.addNew(type: .item)

        #expect(controller.itemDataModel.items.contains(itemId))
        #expect(controller.itemDataModel.items.count == before.count + 1)
        #expect(!before.contains(itemId))
    }

    @Test("A new folder is added like an item", arguments: modules)
    func addFolder(module: NetworkModules) async throws {
        let controller = try itemController(for: module)
        let before = controller.itemDataModel.items.count

        let folderId = await controller.addNew(type: .folder)

        #expect(controller.itemDataModel.items.contains(folderId))
        #expect(controller.itemDataModel.items.count == before + 1)
    }

    @Test("Two new items get different ids", arguments: modules)
    func idsAreUnique(module: NetworkModules) async throws {
        let controller = try itemController(for: module)

        let first = await controller.addNew(type: .item)
        let second = await controller.addNew(type: .item)

        #expect(first != second)
        #expect(Set(controller.itemDataModel.items).count == controller.itemDataModel.items.count, "no id is listed twice")
    }

    @Test("Deleting an item removes only that item", arguments: modules)
    func deleteKeepsTheOthers(module: NetworkModules) async throws {
        let controller = try itemController(for: module)
        let kept = await controller.addNew(type: .item)
        let removed = await controller.addNew(type: .item)
        let count = controller.itemDataModel.items.count

        await controller.delete(itemId: removed)

        #expect(!controller.itemDataModel.items.contains(removed))
        #expect(controller.itemDataModel.items.contains(kept))
        #expect(controller.itemDataModel.items.count == count - 1)
    }

    @Test("Deleting an id that is not there changes nothing", arguments: modules)
    func deleteUnknownId(module: NetworkModules) async throws {
        let controller = try itemController(for: module)
        _ = await controller.addNew(type: .item)
        let before = controller.itemDataModel.items

        await controller.delete(itemId: UUID())

        #expect(controller.itemDataModel.items == before)
    }

    @Test("A deleted item can be added again as a new one", arguments: modules)
    func addAfterDelete(module: NetworkModules) async throws {
        let controller = try itemController(for: module)
        let first = await controller.addNew(type: .item)
        await controller.delete(itemId: first)

        let second = await controller.addNew(type: .item)

        #expect(second != first)
        #expect(controller.itemDataModel.items.contains(second))
        #expect(!controller.itemDataModel.items.contains(first))
    }

    @Test("The module of the controller is the module asked for", arguments: modules)
    func controllerBelongsToItsModule(module: NetworkModules) throws {
        let controller = try itemController(for: module)

        #expect(controller.config.module == module)
    }
}
#endif
