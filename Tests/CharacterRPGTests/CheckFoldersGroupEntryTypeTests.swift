// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

/// A group entry converted from a number entry kept its type, and the inspector showed
/// "= 0 Error" for its empty value. Validate Data sets such an entry back to text.
@Suite("checkFolders – group entry type")
@MainActor
struct CheckFoldersGroupEntryTypeTests {
    private struct Group {
        let ownerId: UUID
        let childId: UUID
        let entryId: UUID
    }

    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    /// An owner with one group entry of the given type that points to a hidden group item.
    private func makeGroup(
        in root: CharacterRootModel,
        type: ValueEntryModel.ValueType,
        entryName: String = "Bonus Items",
        childName: String = "Bonus Items",
        value: String = "",
        diceId: UUID? = nil
    ) async -> Group {
        let ownerId = await root.itemController.addNew(type: .item)
        let childId = await root.itemController.addNew(type: .item)

        let child = root.itemController.itemOrEmpty(for: childId)
        child.name = childName
        child.category = .entry
        child.displayState = 1
        child.groupId = ownerId
        root.itemController.replace(model: child, isInsert: false)

        let entry = ValueEntryModel(id: UUID(), name: entryName, type: type, value: value, diceId: diceId, valueId: childId)
        let owner = root.itemController.itemOrEmpty(for: ownerId)
        owner.category = .character
        owner.entries.append(entry)
        root.itemController.replace(model: owner, isInsert: false)
        return Group(ownerId: ownerId, childId: childId, entryId: entry.id)
    }

    private func entry(_ group: Group, in root: CharacterRootModel) throws -> ValueEntryModel {
        try #require(root.itemController.itemOrEmpty(for: group.ownerId).entries.first { $0.id == group.entryId })
    }

    private func encodedEntries(_ itemId: UUID, in root: CharacterRootModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(root.itemController.itemOrEmpty(for: itemId).entries)
    }

    @Test("A number or decimal group entry is set back to text", arguments: [ValueEntryModel.ValueType.number, .decimal])
    func calculableGroupEntryBecomesText(type: ValueEntryModel.ValueType) async throws {
        let root = try await makeRoot()
        let diceId = UUID()
        let group = await makeGroup(in: root, type: type, diceId: diceId)

        await root.checkFolders(reportModel: ValidateRepairModel())

        let repaired = try entry(group, in: root)
        #expect(repaired.type == .text)
        #expect(repaired.valueId == group.childId, "still points to its group item")
        #expect(repaired.name == "Bonus Items")
        #expect(repaired.value == "")
        #expect(repaired.diceId == diceId)
    }

    @Test("A text or selection group entry keeps its type", arguments: [ValueEntryModel.ValueType.text, .selection])
    func otherGroupEntryTypesAreKept(type: ValueEntryModel.ValueType) async throws {
        let root = try await makeRoot()
        let group = await makeGroup(in: root, type: type)

        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(try entry(group, in: root).type == type)
    }

    @Test("An entry that is no group keeps its number type", arguments: [ValueEntryModel.ValueType.number, .decimal])
    func plainEntryKeepsItsType(type: ValueEntryModel.ValueType) async throws {
        let root = try await makeRoot()
        let ownerId = await root.itemController.addNew(type: .item)
        let plain = ValueEntryModel(id: UUID(), name: "Strength", type: type, value: "12")
        let owner = root.itemController.itemOrEmpty(for: ownerId)
        owner.category = .character
        owner.entries.append(plain)
        root.itemController.replace(model: owner, isInsert: false)

        await root.checkFolders(reportModel: ValidateRepairModel())

        let kept = try #require(root.itemController.itemOrEmpty(for: ownerId).entries.first { $0.id == plain.id })
        #expect(kept.type == type)
        #expect(kept.value == "12")
    }

    @Test("The type and a stale name are repaired in the same run")
    func typeAndNameAreRepairedTogether() async throws {
        let root = try await makeRoot()
        let group = await makeGroup(in: root, type: .number, entryName: "Old name", childName: "Bonus Items")

        await root.checkFolders(reportModel: ValidateRepairModel())

        let repaired = try entry(group, in: root)
        #expect(repaired.type == .text)
        #expect(repaired.name == "Bonus Items")
    }

    @Test("A repeated run leaves the repaired entries unchanged")
    func repeatedRunIsStable() async throws {
        let root = try await makeRoot()
        let group = await makeGroup(in: root, type: .number)

        await root.checkFolders(reportModel: ValidateRepairModel())
        let afterFirst = try encodedEntries(group.ownerId, in: root)
        await root.checkFolders(reportModel: ValidateRepairModel())
        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(try encodedEntries(group.ownerId, in: root) == afterFirst, "the entry's clock must not move on a repeated run")
    }

    @Test("A text group entry is not written at all")
    func alreadyTextEntryIsNotRewritten() async throws {
        let root = try await makeRoot()
        let group = await makeGroup(in: root, type: .text)
        let before = try encodedEntries(group.ownerId, in: root)

        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(try encodedEntries(group.ownerId, in: root) == before)
    }

    @Test("The group entry of a hidden owner is not touched")
    func hiddenOwnerIsNotTouched() async throws {
        let root = try await makeRoot()
        let group = await makeGroup(in: root, type: .number)
        let owner = root.itemController.itemOrEmpty(for: group.ownerId)
        owner.displayState = DisplayStateMask.totalHidden.rawValue
        root.itemController.replace(model: owner, isInsert: false)

        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(try entry(group, in: root).type == .number)
    }

    @Test("After the repair the inspector row shows no calculated value")
    func repairedRowShowsNoError() async throws {
        let root = try await makeRoot()
        let group = await makeGroup(in: root, type: .number)

        await root.checkFolders(reportModel: ValidateRepairModel())

        let owner = root.itemController.itemOrEmpty(for: group.ownerId)
        let text = root.linkController.linkText(model: owner, entry: try entry(group, in: root))
        #expect(!text.contains("Error"), Comment(rawValue: text))
        #expect(!text.contains("= "), Comment(rawValue: text))
    }
}
