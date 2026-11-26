// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    DetailFolderListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), folderListController: root.folderListController)
}

struct DetailFolderListView: View {
    let root: AudioRootModel
    let model: AudioModel
    let folderListController: FolderListController
    var isSubFolder: Bool = false

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
        DetailFolderList(
            root: root.rootController,
            openFileWindowModel: root.openFileWindowModel,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self,
            showsBottomOverlayBar: !usesPhoneTabAccessory,
            bottomOverlayBarHeight: bottomOverlayBarHeight
        ) {
            AudioPlayerBarView()
#if os(visionOS)
                // `glassEffect` (the bar's background elsewhere) does not exist on visionOS: the
                // player gets the system glass here, not inside `AudioPlayerBarView`, because the
                // game table panel and the toolbar popover already stand on glass of their own.
                .padding()
                .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
#endif
                .padding()
        } editor: {
            DetailEditorView(root: root, model: model)
        } viewer: { itemId, dismiss in
            root.viewController.viewer(
                root: root,
                itemId: itemId,
                configuration: ViewerConfiguration(closeButton: true),
                dismissAction: dismiss
            )
        }
    }

    /// The fixed 80 pt fits the one-row bar. The visionOS bar has a second row (the position
    /// slider) and now covers the rows under it with glass, so the inset measures the bar itself.
    private var bottomOverlayBarHeight: CGFloat? {
#if os(visionOS)
        nil
#else
        80
#endif
    }

    private var usesPhoneTabAccessory: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }
}
