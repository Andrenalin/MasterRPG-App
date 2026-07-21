// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController: Sendable {
    public init() {}

    public let sharingViewType: SharingViewType = .none
    public let thumbnailRowViewType: ThumbnailRowViewType = .none
}

extension ViewController: ViewControllable {}

public extension ViewController {
    @MainActor
    func gameListView(root: RuleRootModel) -> some View {
        LinkRootView(type: .inspector, itemSelectionModel: ItemSelectionModel())
    }

    @MainActor
    func linkListView(
        type: LinkRootType,
        itemSelectionModel: ItemSelectionModel
    ) -> some View {
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }

    @MainActor
    func viewer(
        root: RuleRootModel,
        itemId: UUID,
        configuration: ViewerConfiguration,
        dismissAction: (() -> Void)? = nil
    ) -> some View {
        ViewerRootView(
            model: root.itemController.itemOrEmpty(for: itemId),
            configuration: configuration,
            dismissAction: dismissAction
        )
    }

    @MainActor
    func windowViewer(root: RuleRootModel, selection: WindowItemSelection) -> some View {
        viewer(
            root: root,
            itemId: selection.itemId,
            configuration: ViewerConfiguration(closeButton: false)
        )
    }

    @MainActor
    func gameViewer(root: RuleRootModel) -> some View {
        ViewerRootView(
            model: root.gameController.currentItem(),
            configuration: ViewerConfiguration(closeButton: false, addToolbar: false, isGame: true)
        )
    }
}
