// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

/// Validate Folders rewrote the group entries of table-generated items on every run: the group
/// item's name is a markdown link, the repair stored its link-free text, and the next run compared
/// that text with the raw link name again. Each rewrite moved the entry's sync clock, so the item
/// counted as changed (and synced) every time.
@Suite("checkFolders – group entry names")
@MainActor
struct CheckFoldersEntryNameTests {
    private let linkedName = "[Lederschienen](RPG://TABLES/0/A5CD92DC-89D7-42DA-B103-361966F53876/3D3F744C-D004-4615-BBAF-ECED7D55EC38)"

    /// An owner with one group entry that points to a hidden group item.
    private func makeGroup(
        in root: CharacterRootModel,
        childName: String,
        childDescription: String,
        entryName: String,
        entryValue: String
    ) async -> (ownerId: UUID, childId: UUID) {
        let ownerId = await root.itemController.addNew(type: .item)
        let childId = await root.itemController.addNew(type: .item)

        let child = root.itemController.itemOrEmpty(for: childId)
        child.name = childName
        child.description = childDescription
        child.displayState = 1
        child.groupId = ownerId
        child.parentId = nil
        root.itemController.replace(model: child, isInsert: false)

        let owner = root.itemController.itemOrEmpty(for: ownerId)
        owner.entries.append(ValueEntryModel(id: UUID(), name: entryName, type: .text, value: entryValue, valueId: childId))
        root.itemController.replace(model: owner, isInsert: false)
        return (ownerId, childId)
    }

    private func encoded(_ itemId: UUID, in root: CharacterRootModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(root.itemController.itemOrEmpty(for: itemId))
    }

    private func encodedEntries(_ itemId: UUID, in root: CharacterRootModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(root.itemController.itemOrEmpty(for: itemId).entries)
    }

    @Test("A group item named by a link is written once as plain text and then left alone")
    func linkNamedGroupEntryIsStable() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let (ownerId, _) = await makeGroup(in: root, childName: linkedName, childDescription: "Leather greaves", entryName: "Old name", entryValue: "old")

        await root.checkFolders(reportModel: ValidateRepairModel())

        let first = root.itemController.itemOrEmpty(for: ownerId)
        let entry = try #require(first.entries.first)
        #expect(entry.name == "Lederschienen")
        #expect(entry.value == "Leather greaves")

        let afterFirst = try encoded(ownerId, in: root)
        await root.checkFolders(reportModel: ValidateRepairModel())
        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(try encoded(ownerId, in: root) == afterFirst, "the entry's clock must not move on a repeated run")
    }

    @Test("An entry that already shows the link-free name is not touched on the first run either")
    func alreadyCurrentEntryIsNotRewritten() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let (ownerId, _) = await makeGroup(in: root, childName: linkedName, childDescription: "Leather greaves", entryName: "Lederschienen", entryValue: "kept")
        let before = try encodedEntries(ownerId, in: root)

        await root.checkFolders(reportModel: ValidateRepairModel())

        let entry = try #require(root.itemController.itemOrEmpty(for: ownerId).entries.first)
        #expect(entry.name == "Lederschienen")
        #expect(entry.value == "kept")
        #expect(try encodedEntries(ownerId, in: root) == before)
    }

    @Test("A plain-named group item keeps the entry's own value")
    func plainNamedGroupEntryKeepsItsValue() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let (ownerId, _) = await makeGroup(in: root, childName: "Waffen", childDescription: "Group description", entryName: "Waffen", entryValue: "custom value")
        let before = try encodedEntries(ownerId, in: root)

        await root.checkFolders(reportModel: ValidateRepairModel())
        await root.checkFolders(reportModel: ValidateRepairModel())

        let entry = try #require(root.itemController.itemOrEmpty(for: ownerId).entries.first)
        #expect(entry.value == "custom value")
        #expect(try encodedEntries(ownerId, in: root) == before)
    }

    @Test("A renamed group item still updates the entry")
    func renamedGroupItemUpdatesEntry() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let (ownerId, childId) = await makeGroup(in: root, childName: "Waffen", childDescription: "Group description", entryName: "Waffen", entryValue: "x")

        let child = root.itemController.itemOrEmpty(for: childId)
        child.name = "Rüstung"
        child.description = "New description"
        root.itemController.replace(model: child, isInsert: false)
        await root.checkFolders(reportModel: ValidateRepairModel())

        let entry = try #require(root.itemController.itemOrEmpty(for: ownerId).entries.first)
        #expect(entry.name == "Rüstung")
        #expect(entry.value == "New description")
    }
}
