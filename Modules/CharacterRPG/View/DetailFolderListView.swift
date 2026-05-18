// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: CharacterRootModel
    let model: ValueModel

    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: CharacterDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false
    
    var body: some View {
        let _ = Self._printChanges()

        content
            .onAppear {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
            }
            .applyIf(appSizeModel.mode == .compact) {
                $0.navigate(to: $detailRoute)
                    .onChange(of: currentListModel.subFolderRoute) {
                        guard let subItemId = currentListModel.subFolderRoute else { return }
                        detailRoute = CharacterDetailRoute.folder(subItemId)
                    }
                    .onChange(of: detailRoute) { _, _ in
                        guard detailRoute == nil else { return }
                        currentListModel.resetListModel()
                    }
            }
            .applyIf(appSizeModel.mode == .regular) {
                $0.background {
                    FolderItemsObserver(
                        navigationModel: root.navigationModel,
                        lastFolderId: $lastFolderId,
                        showFolderDetail: $showFolderDetail
                    )
                }
                .overlay {
                    if showFolderDetail, let lastFolderId {
                        CharacterDetailRoute.folderInline(lastFolderId)
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
            }
    }
    
    // MARK: - Computed Properties
    
    /// Returns the current list model for this view's model, creating it if needed
    private var currentListModel: FolderListModel {
        if let existing = root.navigationModel.folderModels[model.id] {
            return existing
        }
        
        let newModel = root.folderListController.copyModel(parentModel: model)
        root.navigationModel.folderModels[model.id] = newModel
        return newModel
    }
    
    /// Creates a controller instance for the current list model
    private var detailListController: FolderListControllable {
        root.folderListController.copy(listModel: currentListModel)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var content: some View {
        ItemDetailRootView(
            root: root.rootController,
            detailListController: detailListController,
            selectedModel: model,
            configuration: .init(),
            linkTypes: LinkCharacterModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        }
        .overlay {
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
    
    // MARK: - Actions
    
    private func closeFolderOverlay() {
        showFolderDetail = false
        lastFolderId = nil
        currentListModel.resetListModel()
    }
}

// MARK: - Supporting Views



private struct FolderItemsObserver: View {
    let navigationModel: ModuleNavigationModel
    @Binding var lastFolderId: UUID?
    @Binding var showFolderDetail: Bool

    var body: some View {
        Color.clear
            .onChange(of: navigationModel.folderItems) {
                guard lastFolderId == nil, let subItemId = navigationModel.folderItems.last else { return }
                lastFolderId = subItemId
                withAnimation {
                    showFolderDetail = true
                }
            }
    }
}
