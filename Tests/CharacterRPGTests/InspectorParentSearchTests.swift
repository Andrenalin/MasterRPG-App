// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

/// CODE_AUDIT_TestGaps §5.15: the inspector search scoped to one character
/// (`inspectorSearchResults(searchText:parentId:)`, its `characterInspectorResult` and
/// `collectValueEntries`): which entries match, how results nest, and the recursion guard.
@MainActor
@Suite("Inspector search scoped to a character")
struct InspectorParentSearchTests {
    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    private func addCharacter(_ root: CharacterRootModel, name: String, entries: [(name: String, content: String)] = []) async -> (id: UUID, entryIds: [UUID]) {
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: name, itemId: itemId)
        var ids: [UUID] = []
        for entry in entries {
            let model = ValueEntryModel(id: UUID(), name: entry.name, type: .text, value: entry.content)
            root.editController.add(entry: model, itemId: itemId)
            ids.append(model.id)
        }
        return (itemId, ids)
    }

    @Test("A matching entry becomes a child of its character, matched by name or content")
    func matchingEntriesAreChildren() async throws {
        let root = try await makeRoot()
        let hero = await addCharacter(root, name: "Thorin", entries: [
            ("Strength", "18"), ("Backstory", "Raised in the Iron Hills"), ("Dexterity", "12")
        ])

        let byName = await root.searchController.inspectorSearchResults(searchText: "Strength", parentId: hero.id)
        let byContent = await root.searchController.inspectorSearchResults(searchText: "Iron Hills", parentId: hero.id)

        let nameResult = try #require(byName.first)
        #expect(byName.count == 1)
        #expect(nameResult.itemId == hero.id)
        #expect(nameResult.children.map(\.entryId) == [hero.entryIds[0]])
        let contentResult = try #require(byContent.first)
        #expect(contentResult.children.map(\.entryId) == [hero.entryIds[1]])
    }

    @Test("Without a match in the character or its entries nothing is returned")
    func noMatchReturnsNothing() async throws {
        let root = try await makeRoot()
        let hero = await addCharacter(root, name: "Thorin", entries: [("Strength", "18")])

        let results = await root.searchController.inspectorSearchResults(searchText: "zzzz", parentId: hero.id)

        #expect(results.isEmpty)
    }

    @Test("A character whose name matches is returned without children when no entry matches")
    func nameMatchWithoutEntries() async throws {
        let root = try await makeRoot()
        let hero = await addCharacter(root, name: "Thorin Oakenshield", entries: [("Strength", "18")])

        let results = await root.searchController.inspectorSearchResults(searchText: "Oakenshield", parentId: hero.id)

        let result = try #require(results.first)
        #expect(result.itemId == hero.id)
        #expect(result.children.isEmpty)
    }

    @Test("An unknown character gives nothing")
    func unknownParent() async throws {
        let root = try await makeRoot()

        let results = await root.searchController.inspectorSearchResults(searchText: "x", parentId: UUID())

        #expect(results.isEmpty)
    }

    @Test("Entries of a group are found and reported against the character, not the group's item")
    func groupEntriesBelongToTheCharacter() async throws {
        let root = try await makeRoot()
        let hero = await addCharacter(root, name: "Thorin")
        let groupEntryId = await root.editController.addNewGroup(itemId: hero.id)
        let groupItemId = try #require(root.itemController.itemOrEmpty(for: hero.id).entries.first { $0.id == groupEntryId }?.valueId)
        let subEntryId = await root.editController.addNewGroup(itemId: groupItemId)
        root.editController.update(itemId: groupItemId, entryId: subEntryId, name: "Hidden Talent", content: "")

        let results = await root.searchController.inspectorSearchResults(searchText: "Talent", parentId: hero.id)

        let result = try #require(results.first)
        #expect(result.itemId == hero.id)
        let child = try #require(result.children.first)
        #expect(child.entryId == subEntryId)
        #expect(child.itemId == hero.id, "the link target is the character, so the UI navigates to the character sheet")
    }

    @Test("A group that links back to its own item does not recurse forever")
    func cyclicGroupTerminates() async throws {
        let root = try await makeRoot()
        let hero = await addCharacter(root, name: "Loop")
        var cyclic = ValueEntryModel(id: UUID(), name: "Self", type: .text, value: "needle")
        cyclic.valueId = hero.id
        root.editController.add(entry: cyclic, itemId: hero.id)

        let results = await root.searchController.inspectorSearchResults(searchText: "needle", parentId: hero.id)

        // Found, and each level adds the entry again, bounded by the depth limit.
        let count = results.first?.children.count ?? 0
        #expect(count >= 1)
        #expect(count <= FolderTreeDepthLimit.max + 1)
    }

    @Test("Matching is localized and diacritic-insensitive, like the other searches")
    func matchingIsLocalizedStandard() async throws {
        let root = try await makeRoot()
        let hero = await addCharacter(root, name: "Thorin", entries: [("Größe", "Zwerg")])

        let results = await root.searchController.inspectorSearchResults(searchText: "grosse", parentId: hero.id)

        #expect(results.first?.children.count == 1)
    }
}
