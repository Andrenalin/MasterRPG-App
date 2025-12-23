// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    public let goupViewType: GroupViewType = .photo
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {}

// MARK: Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }

    @MainActor func inlineViewer(root: PdfRootModel, with id: UUID, withoutBookmark: Bool, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: id)
        return ViewerRootView(model: model, entryId: nil, withoutBookmark: withoutBookmark, dismissAction: dismissAction)
    }
    
    @MainActor func windowViewer(root: PdfRootModel, selection: WindowItemSelection) -> some View {
        let model = root.itemController.itemOrEmpty(for: selection.itemId)
        return ViewerRootView(model: model, entryId: selection.entryId, windowMode: true, withoutBookmark: false)
    }
    
    @MainActor func gameView(root: PdfRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
}

public extension ViewController {
    @MainActor func gamePdfView(root: PdfRootModel) -> some View {
        ViewerRootView(model: root.gameController.currentItem(), entryId: nil, withoutBookmark: true, dismissAction: nil)
            .padding(32)
            .padding(.top, 64)
            .environment(root)
            .environment(\.showGame, true)
    }
}
