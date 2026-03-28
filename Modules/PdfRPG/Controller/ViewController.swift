// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct ViewController {
    public let goupViewType: GroupViewType = .none
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {
    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }
}

// MARK: Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type)
            .environment(itemSelectionModel)
    }

    @MainActor func viewer(root: PdfRootModel, itemId: UUID, entryId: UUID?, configuration: ViewerConfiguration, onTextExtracted: ((String) -> Void)? = nil, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        return ViewerRootView(model: model, entryId: entryId, configuration: configuration, onTextExtracted: onTextExtracted, dismissAction: dismissAction)
    }
    
    @MainActor func gameView(root: PdfRootModel) -> some View {
        LinkRootView(type: .inspector)
            .environment(ItemSelectionModel())
    }
}

public extension ViewController {
    @MainActor func gamePdfView(root: PdfRootModel) -> some View {
        ViewerRootView(model: root.gameController.currentItem(), entryId: nil, configuration: ViewerConfiguration(isGame: true), dismissAction: nil)
            .padding(32)
            .padding(.top, 64)
            .environment(root)
            .environment(\.showGame, true)
    }
}
