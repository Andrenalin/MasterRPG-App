// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    @Environment(OpenFileWindowModel.self) private var openFileWindowModel
    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: AdventureDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false

    var detailFolderListController: FolderListController {
        let _ = print("🔄 DetailFolderListView.detailFolderListController computed for model: \(model.name)")
        let listModel = root.navigationModel.folderModels[model.id]

        let allListModel = listModel ?? root.folderListController.copyModel(parentModel: model)
        if listModel == nil {
            root.navigationModel.folderModels[model.id] = allListModel
        }

        return root.folderListController.copy(listModel: allListModel) as! FolderListController
    }

    var body: some View {
        let _ = Self._printChanges()
        content(listController: detailFolderListController)
            .applyIf(appSizeModel.mode == .compact) {
                $0.navigate(to: $detailRoute)
                    .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                        guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                        detailRoute = AdventureDetailRoute.folder(subItemId)
                    }
                    .onChange(of: detailRoute) { oldRoute, newRoute in
                        guard detailRoute == nil else { return }
                        detailFolderListController.listModel.resetListModel()
                    }
            }
            .applyIf(appSizeModel.mode == .regular) {
                $0.onChange(of: root.navigationModel.folderItems) {
                    guard lastFolderId == nil, let subItemId = root.navigationModel.folderItems.last else { return }
                    lastFolderId = subItemId
                    withAnimation {
                        showFolderDetail = true
                    }
                }
                .overlay {
                    if showFolderDetail, let lastFolderId {
                        AdventureDetailRoute.folderInline(lastFolderId)
                            .padding(.top, 36)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button {
                                        showFolderDetail = false
                                        self.lastFolderId = nil
                                        detailFolderListController.listModel.resetListModel()
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

    @ViewBuilder
    func content(listController: any FolderListControllable) -> some View {
        let _ = print("🔍 DetailFolderListView.content() called for model: \(model.name)")
        ItemDetailRootView(
            detailListController: listController,
            selectedModel: model,
            configuration: .init(editorAsBackground: false, hasOverlay: false)
        ) {
            EmptyView()
        } editor: {
            detailEditorView
        } overlay: {
            EmptyView()
        } entryEditor: {
            EntryEditorView(editController: root.editController, model: model, linkControllable: root.linkControllable, linkTypes: LinkAdventureModuleTransferable.self)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.viewer(root: root, itemId: openFileWindowModel.itemId, configuration: ViewerConfiguration(closeButton: true)) {
                    openFileWindowModel.showItem = false
                }
            }
        }
    }

    @ViewBuilder private var detailEditorView: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.adventureEditModel.selectionDice)
            .onChange(of: root.editController.adventureEditModel.selectionDice.selection) {
                withAnimation { root.editController.add(diceId: root.editController.adventureEditModel.selectionDice.itemId, itemId: model.id) }
            }
            .task(id: model.diceId) {
                // Sync dice selection without triggering animation on initial render
                root.editController.adventureEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }

        root.photoRoot.viewController.dropSelectionView(model: root.editController.adventureEditModel.selectionPhoto)
            .onChange(of: root.editController.adventureEditModel.selectionPhoto.itemId) {
                withAnimation { root.editController.add(photoId: root.editController.adventureEditModel.selectionPhoto.itemId, itemId: model.id) }
            }
            .task(id: model.photoId) {
                // Sync photo selection without triggering animation on initial render
                root.editController.adventureEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil)
            }

        SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, model: model, module: root.config.module, headerTitle: String(localized: "Sections", bundle: .module).localizedString, linkTypes: LinkAdventureModuleTransferable.self)
            .id(model.id)
    }
}
