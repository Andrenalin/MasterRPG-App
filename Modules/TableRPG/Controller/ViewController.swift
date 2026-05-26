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
}

extension ViewController: ViewControllable {
    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailDiceRow(itemId: itemId).equatable())
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
    public var supportsBatchExtraction: Bool { true }

    @MainActor public func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView? {
        guard let tableController = itemController as? ItemController else { return nil }
        let formatEntries: @MainActor @Sendable (UUID) -> String = { id in
            let model = tableController.itemOrEmpty(for: id)
            var lines: [String] = []
            if !model.name.isEmpty {
                lines.append("Table: \(model.name)")
                lines.append("")
            }
            for entry in model.entries {
                lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
            }
            return lines.joined(separator: "\n")
        }
        return AnyView(
            BatchTextSummaryExtractionView(
                module: .table,
                ids: ids,
                itemController: itemController,
                editController: editController,
                formatEntries: formatEntries
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
