// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG

public struct ViewController: Sendable {
    public let goupViewType: GroupViewType = .none
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId).equatable())
    }
    
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }
}

// MARK: External Views

extension ViewController {
    @MainActor
    func diceSelection(root: AdventureRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.dropChooseView(model: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func dropChooseView(model: ItemSelectionModel) -> some View {
        DropChooseView(selectionModel: model)
            .environment(model)
    }
    
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }
    
    @MainActor func inlineViewer(root: AdventureRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return AdventureSheet(model: model, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: AdventureRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return AdventureSheet(model: model, dismissAction: nil)
    }
    
    @MainActor func gameView(root: AdventureRootModel, focusedIds: [UUID]) -> some View {
        Group {
            if let select = focusedIds.first {
                windowViewer(root: root, selection: WindowItemSelection(itemId: select))
            } else {
                LinkRootView(type: .inspector)
                    .environment(ItemSelectionModel())
            }
        }
    }
    
    @MainActor func gameModuleListView(root: AdventureRootModel, isPlayer: Bool) -> some View {
        EditorLinkView(root: root.rootController, model: AdventureModel.empty, editorLinkModel: isPlayer ? root.playerLinkModel : root.editorLinkModel)
    }
}
