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

    @MainActor public func thumbnailRowView(for model: any ItemDataAccessible) -> AnyView {
        AnyView(ThumbnailDiceRow(itemId: model.id, item: model as? DiceModel).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }

    // No 4-arg override: `InlineRowViewer` here delegates to `DiceInline`,
    // which resolves via `gameController.gameItem(for:)` (game-session
    // state), not `itemController.itemSync`/`itemOrEmpty` — so it isn't
    // part of the `itemData`-whole-dictionary subscription this override
    // exists to avoid. The 2-arg protocol default already covers this
    // correctly. See CODE_AUDIT_10 §8.1.
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

    @MainActor func overlayGameView(root: DiceRootModel) -> some View {
        RootDiceOverlay()
            .environment(root)
    }
}

// MARK: - Dice

public extension ViewController {
    @MainActor
    func viewDice(root: DiceRootModel, with id: UUID?, for resultCategory: ResultCategory, player: Bool) -> some View {
        DiceInline(itemId: id ?? UUID(), resultCategory: resultCategory, player: player)
    }
}

extension ViewController {
    /// Base row height with no extra result rows — matches `DieViewerView`'s
    /// 44pt die circle plus its padding/shadow chrome. See CODE_AUDIT §8.3.
    private static let baseGameDiceHeight: CGFloat = 82.0
    /// Extra height contributed by each additional stacked result row.
    private static let perResultRowHeight: CGFloat = 36.0
    /// Per-entry width on visionOS vs. other platforms, plus a fixed margin.
    private static let visionOSEntryWidth: CGFloat = 112
    private static let entryWidth: CGFloat = 56
    private static let entryWidthMargin: CGFloat = 20

    @MainActor public func gameDiceHeight(root: DiceRootModel) -> CGFloat {
        guard let itemId = root.gameController.gameModel.currentItemId else { return Self.baseGameDiceHeight }
        let dice = root.gameController.gameItem(for: itemId)
        return height(for: dice)
    }

    @MainActor
    func height(for dice: DiceModel, minResult: Int = 0, maxResult: Int = 25) -> CGFloat {
        var values = dice.dice.reduce(0) { $1.result.count > $0 ? $1.result.count : $0 } - 1
        values = min(max(minResult, values), maxResult)
        return CGFloat(values) * Self.perResultRowHeight + Self.baseGameDiceHeight
    }

    @MainActor
    func width(for dice: DiceModel, maxWidth: CGFloat) -> CGFloat {
        var values = dice.entries.count
        values = max(1, values)
#if os(visionOS)
        return min(CGFloat(values) * Self.visionOSEntryWidth + Self.entryWidthMargin, maxWidth)
#else
        return min(CGFloat(values) * Self.entryWidth + Self.entryWidthMargin, maxWidth)
#endif

    }
}
