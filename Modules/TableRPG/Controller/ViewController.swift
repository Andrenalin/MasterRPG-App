// @copyright André Trettin

import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

public struct ViewController: Sendable {
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
    public let supportsBatchExtraction: Bool = true
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailDiceRow(itemId: itemId).equatable())
    }

    @MainActor public func thumbnailRowView(for model: any ItemDataAccessable) -> AnyView {
        AnyView(ThumbnailDiceRow(itemId: model.id, item: model as? TableModel).equatable())
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
        LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
    }

    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }
}

// MARK: - Batch Extraction

#if !os(tvOS)
extension ViewController {
    @MainActor public func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView? {
        guard itemController is ItemController else { return nil }
        return AnyView(
            BatchTextSummaryExtractionView(
                module: .table,
                ids: ids,
                itemController: itemController,
                editController: editController
            )
        )
    }
}
#endif

// MARK: - Viewers

public extension ViewController {

    @MainActor func viewer(root: TableRootModel, itemId: UUID, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        return ViewerRootView(model: model, configuration: configuration, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: TableRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, configuration: ViewerConfiguration(closeButton: false))
    }

    @MainActor func gameViewer(root: TableRootModel) -> some View {
        ViewerRootView(model: root.gameController.currentItem(), configuration: ViewerConfiguration(closeButton: false, addToolbar: false))
    }
}
