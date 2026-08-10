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
