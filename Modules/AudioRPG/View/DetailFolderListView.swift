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

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        // Deliberately does NOT use the shared `DetailFolderList` (CoreRPG,
        // see CODE_AUDIT §9.3): the audio bar's `safeAreaInset`/`overlay`
        // must sit *between* the editor content and `.openFileWindowOverlay`
        // so the file viewer still renders above the audio bar — wrapping
        // them the other way around (chained onto `DetailFolderList`'s
        // already-composed result) would swap that stacking order.
        ItemDetailRootView(
            root: root.rootController,
            detailListController: folderListController,
            selectedModel: model,
            configuration: .init(isSubFolder: isSubFolder),
            linkTypes: EmptyLinkTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        }
        .applyIf(!usesPhoneTabAccessory) {
            $0.safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
                Color.clear
                    .frame(height: 80)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                AudioPlayerBarView()
                    .padding()
            }
        }
        .openFileWindowOverlay(root.openFileWindowModel) { itemId, dismiss in
            root.viewController.viewer(
                root: root,
                itemId: itemId,
                configuration: ViewerConfiguration(closeButton: true),
                dismissAction: dismiss
            )
        }
    }

    private var usesPhoneTabAccessory: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }
}
