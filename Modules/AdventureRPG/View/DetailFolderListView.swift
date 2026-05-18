// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: AdventureRootModel
    let model: AdventureModel
    
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    
    @State private var detailRoute: AdventureDetailRoute?
    @State private var showFolderOverlay: Bool = false
    
    var body: some View {
        ItemDetailRootView(
            root: root.rootController,
            detailListController: detailListController,
            selectedModel: model,
            configuration: .init(),
            linkTypes: LinkAdventureModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        }
        .overlay {
            overlayContent
        }
        .applyIf(appSizeModel.mode == .compact) {
            $0.navigate(to: $detailRoute)
                .onChange(of: currentListModel.subFolderRoute) { _, newRoute in
                    if let subItemId = newRoute {
                        detailRoute = AdventureDetailRoute.folder(subItemId)
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
    
    @ViewBuilder
    private var overlayContent: some View {
        if root.openFileWindowModel.showItem {
            root.viewController.viewer(
                root: root,
                itemId: root.openFileWindowModel.itemId,
                configuration: ViewerConfiguration(closeButton: true, addToolbar: false)
            ) {
                root.openFileWindowModel.showItem = false
            }
        }
        
        if appSizeModel.mode == .regular,
           showFolderOverlay,
           let folderId = root.navigationModel.folderItems.last {
            AdventureDetailRoute.folderInline(folderId)
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

// MARK: - Detail Editor View

private struct DetailEditorView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.adventureEditModel.selectionDice)
            .onChange(of: root.editController.adventureEditModel.selectionDice.selection) {
                withAnimation { root.editController.add(diceId: root.editController.adventureEditModel.selectionDice.itemId, itemId: model.id) }
            }
            .task(id: model.diceId) {
                root.editController.adventureEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }

        root.photoRoot.viewController.dropSelectionView(model: root.editController.adventureEditModel.selectionPhoto)
            .onChange(of: root.editController.adventureEditModel.selectionPhoto.itemId) {
                withAnimation { root.editController.add(photoId: root.editController.adventureEditModel.selectionPhoto.itemId, itemId: model.id) }
            }
            .task(id: model.photoId) {
                root.editController.adventureEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil)
            }

        SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, editorModel: root.editController.sheetEditorModel, model: model, module: root.config.module, headerTitle: String(localized: "Sections", bundle: .module).localizedString, linkTypes: LinkAdventureModuleTransferable.self)
            .id(model.id)
    }
}
