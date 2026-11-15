// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §10.11 / §10.12: the Simple sheet reconciliation and the numeric input filter.
@MainActor
@Suite("Simple sheet controller reconciliation")
struct SimpleSheetControllerTests {
    private struct Fixture {
        let itemController: SimpleItemController
        let controller: SimpleSheetController
        let rootManager: RootManager
        let itemId: UUID
    }

    private func makeFixture(entries: [SimpleEntryModel]) -> Fixture {
        let config = SimpleModuleConfiguration(module: .photo)
        let itemController = SimpleItemController(
            config: config,
            linkRegisterController: LinkRegisterController(root: nil),
            itemDataModel: ItemDataModel()
        )
        let itemId = UUID()
        itemController.resetModel(with: SimpleModel(id: itemId, entries: entries))
        return Fixture(
            itemController: itemController,
            controller: SimpleSheetController(itemController: itemController),
            rootManager: RootManager.preview(fake: ItemRootController.fake),
            itemId: itemId
        )
    }

    private func sheet(_ fixture: Fixture) -> SheetModel {
        fixture.controller.sheet(root: fixture.rootManager, itemId: fixture.itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: false)
    }

    private func entry(_ name: String) -> SimpleEntryModel {
        SimpleEntryModel(name: name, content: "\(name) content")
    }

    @Test("The sheet shows one row per entry in order")
    func sheetListsEntriesInOrder() {
        let fixture = makeFixture(entries: [entry("A"), entry("B"), entry("C")])

        #expect(sheet(fixture).entries.map(\.name) == ["A", "B", "C"])
    }

    @Test("Reordering the entries reorders the rows and keeps the row objects")
    func reorderKeepsRowIdentity() {
        let a = entry("A"), b = entry("B"), c = entry("C")
        let fixture = makeFixture(entries: [a, b, c])
        let sheet = sheet(fixture)
        let rowForA = sheet.entries[0]

        fixture.itemController.resetModel(with: SimpleModel(id: fixture.itemId, entries: [c, a, b]))
        fixture.controller.update(root: fixture.rootManager, sheetModel: sheet, isEditor: false)

        #expect(sheet.entries.map(\.name) == ["C", "A", "B"])
        #expect(sheet.entries.contains { $0 === rowForA })
    }

    @Test("A removed entry loses its row")
    func removedEntryLosesRow() {
        let a = entry("A"), b = entry("B"), c = entry("C")
        let fixture = makeFixture(entries: [a, b, c])
        let sheet = sheet(fixture)

        fixture.itemController.resetModel(with: SimpleModel(id: fixture.itemId, entries: [a, c]))
        fixture.controller.update(root: fixture.rootManager, sheetModel: sheet, isEditor: false)

        #expect(sheet.entries.map(\.name) == ["A", "C"])
    }

    @Test("A merged-in entry gets a row at its position")
    func mergedEntryGetsRow() {
        let a = entry("A"), c = entry("C")
        let fixture = makeFixture(entries: [a, c])
        let sheet = sheet(fixture)

        fixture.itemController.resetModel(with: SimpleModel(id: fixture.itemId, entries: [a, entry("B"), c]))
        fixture.controller.update(root: fixture.rootManager, sheetModel: sheet, isEditor: false)

        #expect(sheet.entries.map(\.name) == ["A", "B", "C"])
    }

    @Test("A renamed entry updates its row and marks it changed")
    func renamedEntryMarksRowChanged() {
        let a = entry("A")
        let fixture = makeFixture(entries: [a])
        let sheet = sheet(fixture)
        var renamed = a
        renamed.name = "Renamed"

        fixture.itemController.resetModel(with: SimpleModel(id: fixture.itemId, entries: [renamed]))
        fixture.controller.update(root: fixture.rootManager, sheetModel: sheet, isEditor: false)

        #expect(sheet.entries.first?.name == "Renamed")
        #expect(sheet.entries.first?.hasChanged == true)
    }

    @Test("An entry that links to a real item nests that item's entries")
    func linkedEntryNestsChildSheet() {
        let child = SimpleModel(id: UUID(), entries: [entry("Inner")])
        let wrapping = SimpleEntryModel(childId: child.id, name: "Wrapper", content: "")
        let fixture = makeFixture(entries: [wrapping])
        fixture.itemController.resetModel(with: child)

        let nested = sheet(fixture).entries.first?.entries.first

        #expect(nested?.entries.map(\.name) == ["Inner"])
        #expect(nested?.isShown == true)
        #expect(nested?.isFolded == false)
    }
}

@Suite("Numeric input filter")
struct NumericFilterTests {
    struct Case: CustomTestStringConvertible {
        let input: String
        let includeDecimal: Bool
        let separator: String
        let expected: String
        var testDescription: String { "\(input.debugDescription) decimal \(includeDecimal) → \(expected.debugDescription)" }
    }

    static let cases = [
        Case(input: "12a3", includeDecimal: false, separator: ".", expected: "123"),
        Case(input: "-5", includeDecimal: false, separator: ".", expected: "-5"),
        Case(input: "5-", includeDecimal: false, separator: ".", expected: "5"),
        Case(input: "--5", includeDecimal: false, separator: ".", expected: "-5"),
        Case(input: "1.2.3", includeDecimal: true, separator: ".", expected: "1.23"),
        Case(input: "1.5", includeDecimal: false, separator: ".", expected: "15"),
        Case(input: "1,5", includeDecimal: true, separator: ",", expected: "1,5"),
        Case(input: "1.5", includeDecimal: true, separator: ",", expected: "15"),
        Case(input: "١٢", includeDecimal: false, separator: ".", expected: ""),
        Case(input: "", includeDecimal: true, separator: ".", expected: ""),
        Case(input: "-.5", includeDecimal: true, separator: ".", expected: "-.5")
    ]

    @Test("filtered", arguments: cases)
    func filtered(_ testCase: Case) {
        #expect(NumericOnlyViewModifier.filtered(testCase.input, includeDecimal: testCase.includeDecimal, decimalSeparator: testCase.separator) == testCase.expected)
    }
}
