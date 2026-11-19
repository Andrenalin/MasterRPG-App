// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

@MainActor
struct ViewControllerTests {
    @Test func viewFactoriesAndCapabilities() async throws {
        let root = DiceRootModel.testRoot()
        let sut = ViewController()
        let itemId = UUID()
        let dice = DiceModel(
            id: itemId,
            name: "Viewer Dice",
            dice: [
                DieModel(id: UUID(), die: .six, result: [1]),
                DieModel(id: UUID(), die: .twenty, result: [4, 8])
            ]
        )
        root.itemController.replace(model: dice, isInsert: true)
        let source = ItemRowModel(itemId: itemId, typeId: .dice)
        let selectionModel = ItemSelectionModel(selection: [WindowItemSelection(itemId: itemId)])

        _ = sut.thumbnailRowView(for: itemId)
        _ = sut.thumbnailRowView(for: dice)
        _ = sut.rowViewer(source: source, destination: source)
        _ = sut.dropChooseView(model: selectionModel)
        _ = sut.linkListView(type: .inspector, itemSelectionModel: selectionModel)
        _ = sut.viewer(root: root, itemId: itemId, configuration: ViewerConfiguration(closeButton: true), dismissAction: {})
        _ = sut.diceRollView(root: root)
        _ = sut.diceActionBarView(root: root)
        _ = sut.diceResultView(root: root)
        _ = sut.dicePlayerView(root: root)
        _ = sut.overlayGameView(root: root)
        _ = sut.viewDice(root: root, with: itemId, for: ResultCategory(id: UUID(), module: .table), player: true)

        #expect(sut.sharingViewType == .share)
        #expect(sut.thumbnailRowViewType == .custom)
        #expect(sut.hasCustomSpaceAction)
    }

    @Test func diceSizingUsesResultsEntriesAndCurrentGameItem() {
        let _ = DiceRootModel.testRoot()
        let sut = ViewController()
        let dice = DiceModel(
            id: UUID(),
            name: "Sized Dice",
            dice: [
                DieModel(id: UUID(), die: .six, result: [1]),
                DieModel(id: UUID(), die: .twenty, result: [4, 8, 12, 16])
            ],
            entries: [
                ChildEntryModel.newChild(id: UUID()),
                ChildEntryModel.newChild(id: UUID()),
                ChildEntryModel.newChild(id: UUID())
            ]
        )

        #expect(sut.height(for: dice) == 190)
        #expect(sut.height(for: dice, minResult: 1, maxResult: 1) == 118)
    }
}
