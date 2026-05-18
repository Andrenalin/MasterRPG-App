// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: AudioRootModel
    let model: AudioModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: AudioDetailRoute?
    @State private var showFolderOverlay: Bool = false
    
    var body: some View {
        let _ = Self._printChanges()
        
        ItemDetailRootView(
            root: root.rootController,
            detailListController: detailListController,
            selectedModel: model,
            configuration: .init(),
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
        .applyIf(appSizeModel.mode == .compact) {
            $0.navigate(to: $detailRoute)
                .onChange(of: currentListModel.subFolderRoute) { _, newRoute in
                    if let subItemId = newRoute {
                        detailRoute = AudioDetailRoute.folder(subItemId)
                    }
                }
                .onChange(of: detailRoute) { _, newRoute in
                    if newRoute == nil {
                        currentListModel.resetListModel()
                    }
                }
        }
        .onChange(of: root.navigationModel.folderItems) {
            handleFolderItemsChange()
        }
    }
    
    
    // MARK: - Computed Properties
    
    private var detailListController: FolderListControllable {
        root.folderListController.copy(listModel: currentListModel)
    }
    
    private var currentListModel: FolderListModel {
        if let existing = root.navigationModel.folderModels[model.id] {
            return existing
        }
        
        let newModel = root.folderListController.copyModel(parentModel: model)
        root.navigationModel.folderModels[model.id] = newModel
        return newModel
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
        
        if appSizeModel.mode == .regular,
           showFolderOverlay,
           let folderId = root.navigationModel.folderItems.last {
            AudioDetailRoute.folderInline(folderId)
                .padding(.top, 36)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            closeFolderOverlay()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
                .transition(.move(edge: .bottom))
        }
    }
    
    // MARK: - Actions
    
    private func handleFolderItemsChange() {
        guard appSizeModel.mode == .regular else { return }
        guard !showFolderOverlay, root.navigationModel.folderItems.last != nil else { return }
        
        withAnimation {
            showFolderOverlay = true
        }
    }
    
    private func closeFolderOverlay() {
        showFolderOverlay = false
        currentListModel.resetListModel()
    }
}
