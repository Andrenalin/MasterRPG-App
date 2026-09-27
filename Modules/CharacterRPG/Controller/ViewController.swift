// @copyright André Trettin

import CoreRPG
import PhotoRPG
import TableRPG
import SwiftUI

public struct ViewController {
    public let thumbnailRowViewType: ThumbnailRowViewType = .custom
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
