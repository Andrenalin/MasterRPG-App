// @copyright André Trettin

import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

public struct ViewController: Sendable {
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId).equatable())
    }

    @MainActor public func thumbnailRowView(for model: any ItemDataAccessable) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: model.id, item: model as? AdventureModel).equatable())
    }
}

// MARK: - Batch Extraction

#if !os(tvOS)
extension ViewController {
    public var supportsBatchExtraction: Bool { true }

    @MainActor public func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView? {
        guard itemController is ItemController else { return nil }
        return AnyView(
            BatchTextSummaryExtractionView(
                module: .adventure,
                ids: ids,
                itemController: itemController,
                editController: editController
            )
        )
    }
}
#endif

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
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }
    
    @MainActor func viewer(
        root: AdventureRootModel,
        itemId: UUID,
        configuration: ViewerConfiguration,
        searchContext: SheetSearchContext? = nil,
        dismissAction: (() -> Void)? = nil
    ) -> some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        return AdventureSheet(
            model: model,
            configuration: configuration,
            searchContext: searchContext,
            dismissAction: dismissAction
        )
    }
    
    @MainActor func generatorView(root: AdventureRootModel, selection: WindowItemSelection) -> some View {
        AdventureEditorRoute.generator(selection.itemId)
    }

    @MainActor func gameView(
        root: AdventureRootModel,
        focusedIds: [UUID],
        searchContext: SheetSearchContext? = nil,
        addsSearchable: Bool = true
    ) -> some View {
        Group {
            if let select = focusedIds.first {
                viewer(
                    root: root,
                    itemId: select,
                    configuration: ViewerConfiguration(closeButton: false, addToolbar: addsSearchable),
                    searchContext: searchContext
                )
            } else {
                LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
            }
        }
    }
    
    @MainActor func gameModuleListView(root: AdventureRootModel, isPlayer: Bool) -> some View {
        EditorLinkView(root: root.rootController, model: AdventureModel.empty, editorLinkModel: isPlayer ? root.playerLinkModel : root.editorLinkModel)
    }
}
