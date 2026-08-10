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

    @Test("Selecting a sibling entry in a multi-select table preserves an already-selected entry's nested decisions")
    func multiSelectSiblingChoiceKeepsExistingChildDecisions() throws {
        // Given
        let root = makeRoot()
        let childAFirst = TableEntryModel.fixture(id: .fixture5, name: "1", content: "Silver")
        let childASecond = TableEntryModel.fixture(id: .fixtureAudio, name: "2", content: "Copper")
        let childA = TableModel(
            id: .fixture2,
            name: "Material",
            entries: [childAFirst, childASecond]
        )
        let childB = TableModel(
            id: .fixture4,
            name: "Condition",
            entries: [TableEntryModel.fixture(id: .fixture3, name: "1", content: "Ancient")]
        )
        root.itemController.replace(model: childA, isInsert: true)
        root.itemController.replace(model: childB, isInsert: true)

        let firstEntry = TableEntryModel.fixture(
            id: .fixturePhoto,
            name: "Ring",
            content: root.linkController.generateLink(itemId: childA.id)
        )
        let secondEntry = TableEntryModel.fixture(
            id: .fixtureMap,
            name: "Amulet",
            content: root.linkController.generateLink(itemId: childB.id)
        )
        let table = TableModel(
            id: .fixture1,
            name: "Jewelry",
            entries: [firstEntry, secondEntry]
        )
        root.itemController.replace(model: table, isInsert: true)
        let model = root.generationController.makeModel(itemId: table.id)

        // When: select the first entry and drill into its generated table.
        root.generationController.select(
            entryId: firstEntry.id,
            in: model.root,
            model: model
        )
        let firstChild = try #require(model.root.children.first)
        root.generationController.select(
            entryId: childAFirst.id,
            in: firstChild,
            model: model
        )

        // When: selecting the second (sibling) entry in the multi-select table.
        root.generationController.select(
            entryId: secondEntry.id,
            in: model.root,
            model: model
        )

        // Then: the first entry's child occurrence and its nested decision
        // survive untouched; only the second entry's child is newly added.
        #expect(model.root.children.count == 2)
        let survivingFirstChild = try #require(
            model.root.children.first { $0.sourceEntryId == firstEntry.id }
        )
        #expect(survivingFirstChild.id == firstChild.id)
        #expect(survivingFirstChild.selectedEntries.map(\.id) == [childAFirst.id])
        #expect(model.root.children.contains { $0.sourceEntryId == secondEntry.id })
    }

    @Test("The outcome mirrors the on-screen nesting: nested picks join with '/', sibling picks join with ','")
    func outcomeMirrorsNestedSelectionStructure() throws {
        // Given
        let root = makeRoot()
        let subentry = TableEntryModel.fixture(id: .fixture5, name: "1", content: "Subentry")
        let material = TableModel(
            id: .fixture2,
            name: "Material",
            entries: [subentry]
        )
        root.itemController.replace(model: material, isInsert: true)

        // Content combines its own text with the table link, since a link
        // is what registers the nested "Material" generation — a real
        // designer would word an entry the same way, e.g. "First, made of
        // [Material](...)".
        let first = TableEntryModel.fixture(
            id: .fixturePhoto,
            name: "First",
            content: "First \(root.linkController.generateLink(itemId: material.id))"
        )
        let second = TableEntryModel.fixture(
            id: .fixtureMap,
            name: "Second",
            content: "Second"
        )
        let table = TableModel(
            id: .fixture1,
            name: "Table",
            entries: [first, second]
        )
        root.itemController.replace(model: table, isInsert: true)
        let model = root.generationController.makeModel(itemId: table.id)

        // When: only "first" is selected.
        root.generationController.select(entryId: first.id, in: model.root, model: model)

        // Then: a single selection is shown as its raw content (the link's
        // display name inlined, same as everywhere else in the app).
        #expect(model.currentOutcome == "First Material")

        // When: drilling into "first" and selecting its nested "subentry".
        let firstChild = try #require(model.root.children.first)
        root.generationController.select(entryId: subentry.id, in: firstChild, model: model)

        // Then: the nested pick is appended to its parent entry with " / ".
        #expect(model.currentOutcome == "Table: First Material / Subentry")

        // When: selecting the sibling "second" entry too.
        root.generationController.select(entryId: second.id, in: model.root, model: model)

        // Then: the sibling pick joins the same line with ", ".
        #expect(model.currentOutcome == "Table: First Material / Subentry, Second")
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
        // `rations` has no decision yet (neither selected nor hidden), so
        // this is confirmable but not yet "fully decided".
        #expect(!model.isFullyDecided)

        // When
        root.generationController.hide(
            entryId: rations.id,
            in: model.root,
            model: model
        )

        // Then
        #expect(model.root.hiddenEntryIds == [rations.id])
        #expect(model.canConfirm)
        // Every entry now has an explicit decision.
        #expect(model.isFullyDecided)
        #expect(model.summary?.selections.map(\.entryId) == [rope.id, torch.id])
        #expect(model.summary?.value == "Equipment: Rope, Torch")

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

    @Test("A hand-edited outcome overrides the generated summary value")
    func editedOutcomeOverridesGeneratedSummary() {
        // Given
        let root = makeRoot()
        let entry = TableEntryModel.fixture(id: .fixture2, name: "1", content: "Mace")
        let table = TableModel(
            id: .fixture1,
            name: "Weapon",
            entries: [entry]
        )
        root.itemController.replace(model: table, isInsert: true)
        let model = root.generationController.makeModel(itemId: table.id)

        // When
        root.generationController.select(entryId: entry.id, in: model.root, model: model)

        // Then: nothing edited yet, the generated value is used as-is.
        #expect(model.isFullyDecided)
        #expect(model.summary?.value == "Mace")

        // When: the player hand-finalizes the wording.
        model.editedOutcome = "Rusty Mace"

        // Then
        #expect(model.summary?.value == "Rusty Mace")
        // The structured selections stay untouched — only the display
        // value is overridden.
        #expect(model.summary?.selections.map(\.entryId) == [entry.id])
    }

    private func makeRoot() -> TableRootModel {
        TableRootModel.testRoot(
            diceRoot: DiceRootModel.testRoot(),
            pdfRoot: PdfRootModel.testRoot()
        )
    }
}
