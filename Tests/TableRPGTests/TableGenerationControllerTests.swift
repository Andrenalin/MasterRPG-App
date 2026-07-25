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
