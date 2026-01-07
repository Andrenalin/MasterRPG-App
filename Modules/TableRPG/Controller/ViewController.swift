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
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination))
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

// MARK: - List Views

public extension ViewController {
    @MainActor func gameListView(root: TableRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }

    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }
}

// MARK: - Viewers

public extension ViewController {

    @MainActor func inlineViewer(root: TableRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return ViewerRootView(model: model, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: TableRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, windowMode: true)
    }

    @MainActor func gameViewer(root: TableRootModel) -> some View {
        ViewerRootView(model: root.gameController.currentItem(), windowMode: false)
    }
}

// MARK: Links

public extension ViewController {
    @MainActor
    func selectForScan(root: TableRootModel, ids: Binding<[UUID]?>, entryId: Binding<UUID?>? = nil, entryOnly: Bool = false, dismissAction: @escaping () -> Void) -> some View {
        Text("Todo")
    }
}
