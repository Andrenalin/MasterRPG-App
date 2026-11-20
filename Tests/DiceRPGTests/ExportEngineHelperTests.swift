// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

/// CODE_AUDIT_TestGaps §5.13: the shared export engine (`ExportControllable`), tested once on the
/// simplest module instead of through ten: which folders an export promotes, which it only writes
/// as partial folders, how the traversal handles missing ids and cycles, and the block limit.
@MainActor
@Suite("Export engine helpers")
struct ExportEngineHelperTests {
    private struct Tree {
        let root: DiceRootModel
        let folder: UUID
        let children: [UUID]
    }

    private func makeRoot() async throws -> DiceRootModel {
        let root = DiceRootModel.testRoot()
        await root.itemController.resetData()
        return root
    }

    /// A folder with `count` dice in it.
    private func makeTree(count: Int = 3) async throws -> Tree {
        let root = try await makeRoot()
        let folder = await root.itemController.addNew(type: .folder)
        var children: [UUID] = []
        for _ in 0..<count {
            let child = await root.itemController.addNew(type: .item)
            root.editController.addItem(itemId: child, parentId: folder)
            children.append(child)
        }
        return Tree(root: root, folder: folder, children: children)
    }

    private func ids(_ result: ItemModuleIds) -> Set<UUID> {
        Set(result.ids[.dice, default: []])
    }

    private func partial(_ result: ItemModuleIds) -> Set<UUID> {
        Set(result.partialIds[.dice, default: []])
    }

    // MARK: - Folder promotion

    @Test("A folder with all of its children selected is exported whole")
    func completeFolderIsPromoted() async throws {
        let tree = try await makeTree()

        let result = tree.root.exportController.exporting(ids: Set(tree.children))

        #expect(ids(result) == Set(tree.children + [tree.folder]))
        #expect(partial(result).isEmpty)
    }

    @Test("A folder with only some of its children is written as a partial folder, not promoted")
    func incompleteFolderIsPartial() async throws {
        let tree = try await makeTree()

        let result = tree.root.exportController.exporting(ids: [tree.children[0], tree.children[1]])

        #expect(ids(result) == [tree.children[0], tree.children[1]])
        #expect(partial(result) == [tree.folder])
    }

    @Test("Selecting the folder itself exports its children")
    func folderSelectionExportsChildren() async throws {
        let tree = try await makeTree()

        let result = tree.root.exportController.exporting(ids: [tree.folder])

        #expect(ids(result) == Set(tree.children + [tree.folder]))
    }

    @Test("A promoted inner folder lets its parent be promoted too")
    func promotionCascades() async throws {
        let root = try await makeRoot()
        let outer = await root.itemController.addNew(type: .folder)
        let inner = await root.itemController.addNew(type: .folder)
        let leaf = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: inner, parentId: outer)
        root.editController.addItem(itemId: leaf, parentId: inner)

        let result = root.exportController.exporting(ids: [leaf])

        #expect(ids(result) == [leaf, inner, outer])
        #expect(partial(result).isEmpty)
    }

    @Test("A partial inner folder makes every ancestor folder partial")
    func ancestorsOfAPartialFolderArePartial() async throws {
        let root = try await makeRoot()
        let outer = await root.itemController.addNew(type: .folder)
        let inner = await root.itemController.addNew(type: .folder)
        let selected = await root.itemController.addNew(type: .item)
        let left = await root.itemController.addNew(type: .item)
        root.editController.addItem(itemId: inner, parentId: outer)
        root.editController.addItem(itemId: selected, parentId: inner)
        root.editController.addItem(itemId: left, parentId: inner)

        let result = root.exportController.exporting(ids: [selected])

        #expect(ids(result) == [selected])
        #expect(partial(result) == [inner, outer])
    }

    @Test("An item at the root has no folder around it")
    func rootItemHasNoPartialFolder() async throws {
        let root = try await makeRoot()
        let item = await root.itemController.addNew(type: .item)

        let result = root.exportController.exporting(ids: [item])

        #expect(ids(result) == [item])
        #expect(partial(result).isEmpty)
    }

    @Test("An empty selection exports nothing")
    func emptySelection() async throws {
        let root = try await makeRoot()

        let result = root.exportController.exporting(ids: [])

        #expect(ids(result).isEmpty)
        #expect(partial(result).isEmpty)
    }

    // MARK: - Traversal

    @Test("The traversal visits each id once, follows the children it is given and survives a cycle")
    func traversalDeduplicates() async throws {
        let root = try await makeRoot()
        let a = UUID(), b = UUID(), c = UUID()
        var visits: [UUID: Int] = [:]
        let graph: [UUID: [UUID]] = [a: [b, c], b: [c, a], c: [a, b]]

        let result = root.exportController.bfsExportResults(seedIds: [a]) { id in
            visits[id, default: 0] += 1
            return graph[id]
        }

        #expect(result == [a, b, c])
        #expect(visits.values.allSatisfy { $0 == 1 }, "visited once each: \(visits)")
    }

    @Test("The same id twice in the seed list is visited twice, which leaves the result unchanged")
    func duplicateSeedsAreHarmless() async throws {
        // `ItemModuleIds` already removes duplicates, so the callers never pass them; this pins
        // that the traversal's own dedup covers the ids it discovers, not the seed list.
        let root = try await makeRoot()
        let a = UUID(), b = UUID()
        var visits: [UUID: Int] = [:]

        let result = root.exportController.bfsExportResults(seedIds: [a, a]) { id in
            visits[id, default: 0] += 1
            return id == a ? [b] : []
        }

        #expect(result == [a, b])
        #expect(visits[b] == 1)
    }

    @Test("An id that no longer resolves is skipped and its children are not followed")
    func traversalSkipsMissingIds() async throws {
        let root = try await makeRoot()
        let present = UUID(), missing = UUID(), behindMissing = UUID()

        let result = root.exportController.bfsExportResults(seedIds: [present, missing]) { id in
            switch id {
            case present: []
            case missing: nil
            default: [behindMissing]
            }
        }

        #expect(result == [present])
    }

    @Test("The simple traversal follows a folder's entries but not the cross-links of a leaf")
    func simpleEntriesStopAtLeaves() async throws {
        let tree = try await makeTree(count: 2)

        let fromFolder = tree.root.exportController.exportingSimpleEntries(itemIds: ItemModuleIds(ids: [tree.folder], module: .dice))
        let fromLeaf = tree.root.exportController.exportingSimpleEntries(itemIds: ItemModuleIds(ids: [tree.children[0]], module: .dice))

        #expect(ids(fromFolder) == Set(tree.children + [tree.folder]))
        #expect(ids(fromLeaf) == [tree.children[0]])
        #expect(partial(fromLeaf) == [tree.folder])
    }

    @Test("Finalizing keeps the module's other ids out of the result and merges the partial folders")
    func finalizeStampsTheModule() async throws {
        let tree = try await makeTree()
        var input = ItemModuleIds(ids: [tree.children[0]], module: .dice)
        input.ids[.photo] = [UUID()]

        let result = tree.root.exportController.finalizeExportResults([tree.children[0]], into: input)

        #expect(ids(result) == [tree.children[0]])
        #expect(partial(result) == [tree.folder])
        #expect(result.ids[.photo]?.count == 1, "other modules' ids stay as they were")
    }
}
