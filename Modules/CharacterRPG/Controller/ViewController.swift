// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import PhotoRPG
import TableRPG
import SwiftUI

public struct ViewController {
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
    /// Reads the portrait photo's description and tags for the AI extraction.
    let photoRoot: PhotoRootModel?

    init(photoRoot: PhotoRootModel? = nil) {
        self.photoRoot = photoRoot
    }
}

extension ViewController: ViewControllable {
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination, destinationModel: destinationModel).equatable())
    }

    @MainActor public func thumbnailRowView(for itemId: UUID) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: itemId).equatable())
    }

    @MainActor public func thumbnailRowView(for model: any ItemDataAccessible) -> AnyView {
        AnyView(ThumbnailPhotoRow(itemId: model.id, item: model as? ValueModel).equatable())
    }
}

// MARK: - Batch Extraction

#if !os(tvOS)
extension ViewController {
    public var supportsBatchExtraction: Bool { true }

    @MainActor public func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView? {
        guard let characterController = itemController as? ItemController else { return nil }
        let photoRoot = photoRoot
        return AnyView(
            BatchTextSummaryExtractionView(
                module: .value,
                ids: ids,
                itemController: itemController,
                editController: editController,
                entriesText: { itemId in
                    guard let model = characterController.itemSync(for: itemId) else { return "" }
                    return CharacterSheetText.text(for: model, photoRoot: photoRoot) { characterController.itemSync(for: $0) }
                }
            )
        )
    }
}
#endif

// MARK: - Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }

    @MainActor func viewer(
        root: CharacterRootModel,
        itemId: UUID,
        configuration: ViewerConfiguration,
        dismissAction: (() -> Void)? = nil
    ) -> some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        return ViewerRootView(
            model: model,
            configuration: configuration,
            dismissAction: dismissAction
        )
    }
    
    /// The content of a character viewer window; the game view while a game shows the character.
    @MainActor func windowViewer(root: CharacterRootModel, selection: WindowItemSelection, closeButton: Bool) -> some View {
        CharacterWindowViewer(root: root, itemId: selection.itemId, closeButton: closeButton)
    }

    @MainActor func dropChooseView(model: ItemSelectionModel) -> some View {
        DropChooseView(selectionModel: model)
            .environment(model)
    }
    
    @MainActor func gameView(
        root: CharacterRootModel,
        select: UUID? = nil
    ) -> some View {
        Group {
            if let select {
                viewer(
                    root: root,
                    itemId: select,
                    configuration: ViewerConfiguration(
                        closeButton: false,
                        addToolbar: true,
                        isGame: true
                    )
                )
            } else {
                LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())                
            }
        }
    }
}
