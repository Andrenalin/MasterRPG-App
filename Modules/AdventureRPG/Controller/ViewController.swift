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
    
    @MainActor public func rowViewer(source: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source).equatable())
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
}

// MARK: Links

public extension ViewController {
    @MainActor 
    func selectForScan(root: AdventureRootModel, ids: Binding<[UUID]?>, entryId: Binding<UUID?>? = nil, entryOnly: Bool = false, dismissAction: @escaping () -> Void) -> some View {
        Text("Selection - should be LinkRootView with ItemSelectionModel")
//        viewSelect(root: root) {
//            if let links = ids.wrappedValue {
//                return links.map { ItemRowModel(itemId: $0, entryId: entryId?.wrappedValue, typeId: root.itemController.config.module) }
//            } else {
//                return []
//            }
//        } toggleSelection: { selection, _ in
//            if entryOnly {
//                if ids.wrappedValue?.first == selection.itemId,
//                   entryId?.wrappedValue == selection.entryId
//                {
//                    ids.wrappedValue = nil
//                    entryId?.wrappedValue = nil
//                } else {
//                    ids.wrappedValue = [selection.itemId]
//                    entryId?.wrappedValue = selection.entryId
//                }
//            } else {
//                if let index = ids.wrappedValue?.firstIndex(of: selection.itemId) {
//                    ids.wrappedValue?.remove(at: index)
//                } else {
//                    if ids.wrappedValue == nil {
//                        ids.wrappedValue = []
//                    }
//                    ids.wrappedValue?.append(selection.itemId)
//                }
//            }
//        } dismissAction: {
//            dismissAction()
//        }
    }
}
