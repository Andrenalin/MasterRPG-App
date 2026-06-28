// @copyright André Trettin

import CoreRPG
import SwiftUI

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
        .safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
            // Spacer to reserve space for the overlay
            Color.clear
                .frame(height: 80)
                .allowsHitTesting(false) // Critical: don't block touches
        }
        .overlay(alignment: .bottom) {
            AudioPlayerBarView()
                .padding()
        }
        .overlay {
            overlayContent
        }
    }
    
    // MARK: - Overlays
    
    @ViewBuilder private var overlayContent: some View {
        if root.openFileWindowModel.showItem {
            root.viewController.viewer(
                root: root,
                itemId: root.openFileWindowModel.itemId,
                configuration: ViewerConfiguration(closeButton: true)
            ) {
                root.openFileWindowModel.showItem = false
            }
        }
    }
}
