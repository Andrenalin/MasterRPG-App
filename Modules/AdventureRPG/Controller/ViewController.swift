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
}

// MARK: - Batch Extraction

#if !os(tvOS)
extension ViewController {
    public var supportsBatchExtraction: Bool { true }

    @MainActor public func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView? {
        guard let adventureController = itemController as? ItemController else { return nil }
        let formatEntries: @MainActor @Sendable (UUID) -> String = { id in
            let model = adventureController.itemOrEmpty(for: id)
            var lines: [String] = []
            if !model.name.isEmpty {
                lines.append("Adventure: \(model.name)")
                lines.append("")
            }
            for entry in model.entries {
                lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
            }
            return lines.joined(separator: "\n")
        }
        return AnyView(
            BatchTextSummaryExtractionView(
                module: .adventure,
                ids: ids,
                itemController: itemController,
                editController: editController,
                formatEntries: formatEntries
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
    
    @MainActor func viewer(root: AdventureRootModel, itemId: UUID, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        return AdventureSheet(model: model, configuration: configuration, dismissAction: dismissAction)
    }
    
    @MainActor func generatorView(root: AdventureRootModel, selection: WindowItemSelection) -> some View {
        AdventureEditorRoute.generator(selection.itemId)
    }

    @MainActor func gameView(root: AdventureRootModel, focusedIds: [UUID]) -> some View {
        Group {
            if let select = focusedIds.first {
                viewer(root: root, itemId: select, configuration: ViewerConfiguration(closeButton: false))
            } else {
                LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
            }
        }
    }
    
    @MainActor func gameModuleListView(root: AdventureRootModel, isPlayer: Bool) -> some View {
        EditorLinkView(root: root.rootController, model: AdventureModel.empty, editorLinkModel: isPlayer ? root.playerLinkModel : root.editorLinkModel)
    }
}
