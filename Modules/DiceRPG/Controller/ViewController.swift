// @copyright André Trettin

import CoreRPG
import Observation
import SwiftUI

public struct ViewController {
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    public var hasCustomSpaceAction: Bool { true }
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailDiceRow(itemId: itemId).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }
}

// MARK: Viewer

public extension ViewController {
    @MainActor func dropChooseView(model: ItemSelectionModel) -> some View {
        DropChooseView(selectionModel: model)
            .environment(model)
    }

    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }

    @MainActor func viewer(root: DiceRootModel, itemId: UUID, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        return ViewerRootView(model: model, configuration: configuration, dismissAction: dismissAction)
    }

    @MainActor func gameView(root: DiceRootModel) -> some View {
        LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
    }
}

public extension ViewController {
    @MainActor func diceRollView(root: DiceRootModel) -> some View {
        DiceFocusRoll()
            .environment(root)
    }

    @MainActor func diceActionBarView(root: DiceRootModel) -> some View {
        DiceFocusActionBar()
            .environment(root)
    }

    @MainActor func diceResultView(root: DiceRootModel) -> some View {
        DiceFocusResult()
            .environment(root)
    }

    @MainActor func dicePlayerView(root: DiceRootModel) -> some View {
        DicePlayerRoot()
            .environment(root)
    }

    @MainActor func overlayGameView(root: DiceRootModel, hideDice: Bool) -> some View {
        RootDiceOverlay(hideDice: hideDice)
            .environment(root)
    }
}

// MARK: - Dice

public extension ViewController {
    @MainActor
    func viewCompactDice(root: DiceRootModel, itemId: UUID) -> some View {
        let item = root.itemController.itemOrEmpty(for: itemId)
        return Text(item.inlineText)
    }

    @MainActor
    func viewDice(root: DiceRootModel, with id: UUID?, for resultCategory: ResultCategory, player: Bool) -> some View {
        DiceInline(itemId: id ?? UUID(), resultCategory: resultCategory, player: player)
    }
}

extension ViewController {
    @MainActor public func gameGiceHeight(root: DiceRootModel) -> CGFloat {
        guard let itemId = root.gameController.gameModel.currentItemId else { return 82.0 }
        let dice = root.gameController.gameItem(for: itemId)
        return height(for: dice)
    }

    @MainActor
    func height(for dice: DiceModel, minResult: Int = 0, maxResult: Int = 25) -> CGFloat {
        var values = dice.dice.reduce(0) { $1.result.count > $0 ? $1.result.count : $0 } - 1
        values = min(max(minResult, values), maxResult)
        return CGFloat(values) * 36.0 + 82.0
    }
    
    @MainActor
    func width(for dice: DiceModel, maxWidth: CGFloat) -> CGFloat {
        var values = dice.entries.count
        values = max(1, values)
#if os(visionOS)
        return min(CGFloat(values) * 112 + 20, maxWidth)
#else
        return min(CGFloat(values) * 56 + 20, maxWidth)
#endif

    }
}
