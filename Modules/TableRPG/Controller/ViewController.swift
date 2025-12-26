// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .none
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func rowViewer(source: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source))
    }

    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailDiceRow(itemId: itemId))
    }
}

// MARK: External Views

extension ViewController {
    @MainActor
    func diceSelection(root: TableRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.dropChooseView(model: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }
    
    @MainActor func inlineViewer(root: TableRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return ViewerRootView(model: model, showTopImage: false, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: TableRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, showTopImage: false, windowMode: true)
    }

    @MainActor func gameView(root: TableRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
}

// MARK: - Game

public extension ViewController {
    @MainActor
    func gameTableView(root: TableRootModel) -> some View {
        TableGameSheet()
            .environment(root)
            .environment(\.showGame, true)
    }
}

// MARK: - old

public extension ViewController {    
    @MainActor @ViewBuilder
    func diceView(root: TableRootModel, for id: UUID?, from itemId: UUID) -> some View {
        if let id {
            root.diceRoot.viewController.viewDice(root: root.diceRoot, with: id, for: ResultCategory(id: itemId, module: root.itemController.config.module))
        } else {
            EmptyView()
        }
    }
}

// MARK: Links

public extension ViewController {
    @MainActor
    func selectForScan(root: TableRootModel, ids: Binding<[UUID]?>, entryId: Binding<UUID?>? = nil, entryOnly: Bool = false, dismissAction: @escaping () -> Void) -> some View {
        Text("Todo")
    }
}
