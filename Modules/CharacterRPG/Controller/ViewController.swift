// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import TableRPG
import SwiftUI

public struct ViewController {
    public let goupViewType: GroupViewType = .none
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func rowViewer(source: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source).equatable())
    }

    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId).equatable())
    }
}

// MARK: External Views

extension ViewController {
    @MainActor
    func diceSelection(root: CharacterRootModel, selectionModel: ItemSelectionModel) -> some View {
        root.diceRoot.viewController.dropChooseView(model: selectionModel)
    }
}

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }

    @MainActor func windowViewer(root: CharacterRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return CharacterSheet(model: model, showTopImage: false, dismissAction: nil)
    }

    @MainActor func inlineViewer(root: CharacterRootModel, with id: UUID, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return CharacterSheet(model: model, showTopImage: false, dismissAction: dismissAction)
    }
    
    @MainActor func dropChooseView(model: ItemSelectionModel) -> some View {
        DropChooseView(selectionModel: model)
            .environment(model)
    }
    
    @MainActor func gameView(root: CharacterRootModel, select: UUID? = nil) -> some View {
        var selection: [WindowItemSelection] = []
        if let preSelected = select.map({ WindowItemSelection(itemId: $0)}) {
            selection = [preSelected]
        }
        return LinkRootView(type: .inspector)
            .environment(ItemSelectionModel(selection: selection))
    }
}

// MARK: - OLd Views

public extension ViewController {
    @MainActor 
    func selectForScan(root: CharacterRootModel, ids: Binding<[UUID]?>, dismissAction: @escaping () -> Void) -> some View {
        Text("TodO")
    }
}
