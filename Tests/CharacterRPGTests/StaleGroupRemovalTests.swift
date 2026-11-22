// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

/// Validate Data deletes the group items no entry points to any more, and logs them.
@Suite("Stale group removal")
@MainActor
struct StaleGroupRemovalTests {
    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    /// A hidden group item owned by `ownerId`, optionally referenced by an entry of the owner.
    private func addGroup(to ownerId: UUID, referenced: Bool, in root: CharacterRootModel) async -> UUID {
        let groupId = await root.itemController.addNew(type: .item)
        let group = root.itemController.itemOrEmpty(for: groupId)
        group.name = "Group"
        group.category = .entry
        group.displayState = DisplayStateMask.groupHidden.rawValue
        group.groupId = ownerId
        root.itemController.replace(model: group, isInsert: false)
        if referenced {
            let owner = root.itemController.itemOrEmpty(for: ownerId)
            owner.entries.append(ValueEntryModel(id: UUID(), name: "Group", type: .text, value: "", valueId: groupId))
            root.itemController.replace(model: owner, isInsert: false)
        }
        return groupId
    }

    private func addOwner(in root: CharacterRootModel) async -> UUID {
        let ownerId = await root.itemController.addNew(type: .item)
        let owner = root.itemController.itemOrEmpty(for: ownerId)
        owner.category = .character
        root.itemController.replace(model: owner, isInsert: false)
        return ownerId
    }

    @Test("A group an entry points to is not stale")
    func referencedGroupIsNotStale() async throws {
        let root = try await makeRoot()
        let ownerId = await addOwner(in: root)
        _ = await addGroup(to: ownerId, referenced: true, in: root)

        #expect(await root.staleGroups().isEmpty)
    }

    @Test("A group without an entry is stale, with its nested group")
    func unreferencedGroupIsStale() async throws {
        let root = try await makeRoot()
        let ownerId = await addOwner(in: root)
        let staleId = await addGroup(to: ownerId, referenced: false, in: root)
        let nestedId = await addGroup(to: staleId, referenced: true, in: root)
        let keptId = await addGroup(to: ownerId, referenced: true, in: root)

        let stale = await root.staleGroups()
        #expect(stale.map(\.id) == [staleId])
        #expect(stale.first?.ownerId == ownerId)
        #expect(stale.first?.nestedIds == [nestedId])
        #expect(stale.contains { $0.id == keptId } == false)
    }

    @Test("Removing deletes the stale group with its nested group and keeps the referenced ones")
    func removeDeletesStaleGroups() async throws {
        let root = try await makeRoot()
        let ownerId = await addOwner(in: root)
        let staleId = await addGroup(to: ownerId, referenced: false, in: root)
        let nestedId = await addGroup(to: staleId, referenced: true, in: root)
        let keptId = await addGroup(to: ownerId, referenced: true, in: root)

        await root.removeStaleGroups()

        let items = root.itemController.itemDataModel.items
        #expect(items.contains(staleId) == false)
        #expect(items.contains(nestedId) == false)
        #expect(items.contains(keptId))
        #expect(items.contains(ownerId))
        #expect(await root.staleGroups().isEmpty)
    }

    @Test("A library without stale groups is left alone")
    func removeWithoutStaleGroupsChangesNothing() async throws {
        let root = try await makeRoot()
        let ownerId = await addOwner(in: root)
        let keptId = await addGroup(to: ownerId, referenced: true, in: root)
        let before = root.itemController.itemDataModel.items

        await root.removeStaleGroups()

        #expect(root.itemController.itemDataModel.items == before)
        #expect(root.itemController.itemOrEmpty(for: keptId).groupId == ownerId)
    }
}
