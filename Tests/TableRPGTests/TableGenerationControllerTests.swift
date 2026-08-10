// @copyright André Trettin

import CoreRPG
@testable import DiceRPG
import Foundation
@testable import PdfRPG
import Testing
@testable import TableRPG

@MainActor
@Suite("Table generation")
struct TableGenerationControllerTests {
    struct SelectorCase: Sendable, CustomTestStringConvertible {
        let name: String
        let expected: ClosedRange<Int>?

        var testDescription: String { name }
    }

    @Test(arguments: [
        SelectorCase(name: "1", expected: 1...1),
        SelectorCase(name: "1-3", expected: 1...3),
        SelectorCase(name: "**4 – 6**", expected: 4...6),
        SelectorCase(name: "10 Goblins", expected: 10...10),
        SelectorCase(name: "Mace", expected: nil)
    ])
    func parsesEntrySelectors(testCase: SelectorCase) {
        // Given
        let controller = makeRoot().generationController

        // When
        let result = controller.selectorRange(for: testCase.name)

        // Then
        #expect(result == testCase.expected)
    }

    @Test("Selecting an entry appends every linked table and deselecting restores siblings")
    func selectionExpandsAndCollapsesEveryLinkedTable() throws {
        // Given
        let root = makeRoot()
        let childA = TableModel(
            id: .fixture2,
            name: "Material",
            entries: [TableEntryModel.fixture(id: .fixture3, name: "1", content: "Iron")]
        )
        let childB = TableModel(
            id: .fixture4,
            name: "Condition",
            entries: [TableEntryModel.fixture(id: .fixture5, name: "1", content: "Ancient")]
        )
        root.itemController.replace(model: childA, isInsert: true)
        root.itemController.replace(model: childB, isInsert: true)

        let linkedEntry = TableEntryModel.fixture(
            id: .fixturePhoto,
            name: "1",
            content: "\(root.linkController.generateLink(itemId: childA.id)) \(root.linkController.generateLink(itemId: childB.id))"
        )
        let otherEntry = TableEntryModel.fixture(
            id: .fixtureAudio,
            name: "2",
            content: "Plain"
        )
        let table = TableModel(
            id: .fixture1,
            name: "Weapon",
            diceId: .fixtureMap,
            entries: [linkedEntry, otherEntry]
        )
        root.itemController.replace(model: table, isInsert: true)
        let model = root.generationController.makeModel(itemId: table.id)

        // When
        root.generationController.select(
            entryId: linkedEntry.id,
            in: model.root,
            model: model
        )

        // Then
        #expect(model.root.visibleEntries.map(\.id) == [linkedEntry.id])
        #expect(model.root.children.map(\.tableId) == [childA.id, childB.id])
        #expect(model.occurrences.count == 3)
        // Both children stem from the same entry's multiple table links, so
        // the UI can nest them directly under that entry.
        #expect(model.root.children.map(\.sourceEntryId) == [linkedEntry.id, linkedEntry.id])

        // When
        root.generationController.select(
            entryId: linkedEntry.id,
            in: model.root,
            model: model
        )

        // Then
        #expect(model.root.visibleEntries.map(\.id) == [linkedEntry.id, otherEntry.id])
        #expect(model.root.children.isEmpty)
        #expect(model.occurrences.count == 1)
    }

    @Test("A Table without Dice supports multiple selections and explicit hiding")
    func noDiceTableSupportsMultipleSelections() {
        // Given
        let root = makeRoot()
        let rope = TableEntryModel.fixture(
            id: .fixture2,
            name: "Rope",
            content: "Rope"
        )
        let torch = TableEntryModel.fixture(
            id: .fixture3,
            name: "Torch",
            content: "Torch"
        )
        let rations = TableEntryModel.fixture(
            id: .fixture4,
            name: "Rations",
            content: "Rations"
        )
        let table = TableModel(
            id: .fixture1,
            name: "Equipment",
            entries: [rope, torch, rations]
        )
        root.itemController.replace(model: table, isInsert: true)
        let model = root.generationController.makeModel(itemId: table.id)

        // When
        root.generationController.hide(
            entryId: rope.id,
            in: model.root,
            model: model
        )
        root.generationController.hide(
            entryId: torch.id,
            in: model.root,
            model: model
        )

        // Then
        #expect(
            !root.generationController.canHide(
                entryId: rations.id,
                in: model.root
            )
        )

        // Given
        root.generationController.reset(
            occurrence: model.root,
            model: model
        )

        // When
        root.generationController.select(
            entryId: rope.id,
            in: model.root,
            model: model
        )
        root.generationController.select(
            entryId: torch.id,
            in: model.root,
            model: model
        )

        // Then
        #expect(model.root.visibleEntries.map(\.id) == [rope.id, torch.id, rations.id])
        #expect(model.root.selectedEntries.map(\.id) == [rope.id, torch.id])
        #expect(model.canConfirm)

        // When
        root.generationController.hide(
            entryId: rations.id,
            in: model.root,
            model: model
        )

        // Then
        #expect(model.root.hiddenEntryIds == [rations.id])
        #expect(model.canConfirm)
        #expect(model.summary?.selections.map(\.entryId) == [rope.id, torch.id])
        #expect(model.summary?.value == "Equipment: Rope\nEquipment: Torch")

        // When
        root.generationController.apply(
            result: 3,
            to: model.root,
            model: model
        )

        // Then
        #expect(model.root.selectedEntries.map(\.id) == [rations.id])
        #expect(model.root.hiddenEntryIds.isEmpty)
        #expect(model.root.visibleEntries.map(\.id) == [rope.id, torch.id, rations.id])
        #expect(model.summary?.value == "Rations")
    }

    @Test("Changing a parent selection resets linked Table decisions")
    func parentSelectionChangeResetsChildren() throws {
        // Given
        let root = makeRoot()
        let childFirst = TableEntryModel.fixture(
            id: .fixture3,
            name: "First",
            content: "First"
        )
        let childSecond = TableEntryModel.fixture(
            id: .fixture4,
            name: "Second",
            content: "Second"
        )
        let child = TableModel(
            id: .fixture2,
            name: "Child",
            entries: [childFirst, childSecond]
        )
        root.itemController.replace(model: child, isInsert: true)

        let linkedEntry = TableEntryModel.fixture(
            id: .fixturePhoto,
            name: "Linked",
            content: root.linkController.generateLink(itemId: child.id)
        )
        let plainEntry = TableEntryModel.fixture(
            id: .fixtureAudio,
            name: "Plain",
            content: "Plain"
        )
        let table = TableModel(
            id: .fixture1,
            name: "Root",
            diceId: .fixtureMap,
            entries: [linkedEntry, plainEntry]
        )
        root.itemController.replace(model: table, isInsert: true)
        let model = root.generationController.makeModel(itemId: table.id)
        root.generationController.select(
            entryId: linkedEntry.id,
            in: model.root,
            model: model
        )
        let originalChild = try #require(model.root.children.first)
        root.generationController.select(
            entryId: childFirst.id,
            in: originalChild,
            model: model
        )
        root.generationController.hide(
            entryId: childSecond.id,
            in: originalChild,
            model: model
        )
        #expect(originalChild.isResolved)

        // When
        root.generationController.select(
            entryId: plainEntry.id,
            in: model.root,
            model: model
        )
        root.generationController.select(
            entryId: linkedEntry.id,
            in: model.root,
            model: model
        )

        // Then
        let rebuiltChild = try #require(model.root.children.first)
        #expect(rebuiltChild.id != originalChild.id)
        #expect(rebuiltChild.selectedEntryIds.isEmpty)
        #expect(rebuiltChild.hiddenEntryIds.isEmpty)
        #expect(!rebuiltChild.isResolved)
    }

    @Test("A roll replaces a different selection and preserves the same result")
    func rollResultReplacesSelection() {
        // Given
        let root = makeRoot()
        let first = TableEntryModel.fixture(
            id: .fixture2,
            name: "1-3",
            content: "Mace"
        )
        let second = TableEntryModel.fixture(
            id: .fixture3,
            name: "4-6",
            content: "Sword"
        )
        let table = TableModel(
            id: .fixture1,
            name: "Weapon",
            tableType: .dice,
            diceId: .fixtureMap,
            entries: [first, second]
        )
        root.itemController.replace(model: table, isInsert: true)
        let model = root.generationController.makeModel(itemId: table.id)
        root.generationController.select(
            entryId: first.id,
            in: model.root,
            model: model
        )

        // When
        root.generationController.apply(
            result: 5,
            to: model.root,
            model: model
        )
        root.generationController.apply(
            result: 5,
            to: model.root,
            model: model
        )

        // Then
        #expect(model.root.selectedEntries.map(\.id) == [second.id])
        #expect(model.root.lastRoll == 5)
        #expect(model.canConfirm)
    }

    @Test("A linked-table cycle is ignored only on the active path")
    func cycleProtection() {
        // Given
        let root = makeRoot()
        let rootId = UUID.fixture1
        let childId = UUID.fixture2
        let childEntry = TableEntryModel.fixture(
            id: .fixture3,
            name: "1",
            content: root.linkController.generateLink(itemId: rootId)
        )
        let child = TableModel(
            id: childId,
            name: "Child",
            entries: [childEntry]
        )
        root.itemController.replace(model: child, isInsert: true)

        let rootEntry = TableEntryModel.fixture(
            id: .fixture4,
            name: "1",
            content: root.linkController.generateLink(itemId: childId)
        )
        let table = TableModel(
            id: rootId,
            name: "Root",
            entries: [rootEntry]
        )
        root.itemController.replace(model: table, isInsert: true)
        let model = root.generationController.makeModel(itemId: rootId)

        // When
        root.generationController.select(
            entryId: rootEntry.id,
            in: model.root,
            model: model
        )
        let childOccurrence = model.root.children[0]
        root.generationController.select(
            entryId: childEntry.id,
            in: childOccurrence,
            model: model
        )

        // Then
        #expect(childOccurrence.children.isEmpty)
        #expect(childOccurrence.ignoredCycleNames.count == 1)
        #expect(model.canConfirm)
    }

    @Test("A returned player DiceResult selects its exact table occurrence")
    func consumesCategorizedPlayerResult() {
        // Given
        let root = makeRoot()
        let first = TableEntryModel.fixture(id: .fixture2, name: "1-3", content: "Mace")
        let second = TableEntryModel.fixture(id: .fixture3, name: "4-6", content: "Sword")
        let table = TableModel(
            id: .fixture1,
            name: "Weapon",
            tableType: .dice,
            entries: [first, second]
        )
        root.itemController.replace(model: table, isInsert: true)
        let model = root.generationController.makeModel(itemId: table.id)
        root.generationSessionStore.register(model)
        let dice = DiceModel(
            id: .fixture4,
            name: "d6",
            dice: [DieModel(id: .fixture5, die: .six)]
        )
        let diceResult = DiceResultModel(
            diceModel: dice,
            result: .rolled,
            values: "5",
            sum: 5,
            checked: true
        )

        // When
        let consumed = root.generationSessionStore.consume(
            category: ResultCategory(
                id: model.id,
                childId: model.root.id,
                module: .table
            ),
            diceResult: diceResult
        )

        // Then
        #expect(consumed)
        #expect(model.root.selectedEntryId == second.id)
        #expect(model.root.lastRoll == 5)
        #expect(model.summary?.name == "Weapon")
        #expect(model.summary?.value == "Sword")
    }

    private func makeRoot() -> TableRootModel {
        TableRootModel.testRoot(
            diceRoot: DiceRootModel.testRoot(),
            pdfRoot: PdfRootModel.testRoot()
        )
    }
}
