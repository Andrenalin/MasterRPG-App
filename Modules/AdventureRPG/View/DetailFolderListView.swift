// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: AdventureDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false

    var detailFolderListController: FolderListController {
        let listModel = root.navigationModel.folderModels[model.id]

        let allListModel = listModel ?? root.folderListController.copyModel(parentModel: model)
        if listModel == nil {
            root.navigationModel.folderModels[model.id] = allListModel
        }

        return root.folderListController.copy(listModel: allListModel) as! FolderListController
    }

    var body: some View {
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
            .onAppear {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
            }
    }

    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(
            detailListController: listController,
            selectedModel: model,
            configuration: .init(editorAsBackground: false, hasInspector: true, hasOverlay: false)
        ) {
            EmptyView()
        } editor: {
            detailEditorView
        } inspector: {
            EditorLinkView(root: root.rootController, model: model, editorLinkModel: root.editorLinkModel)
        } overlay: {
            EmptyView()
        } entryEditor: {
            EntryEditorView(editController: root.editController, model: model, linkTypes: LinkAdventureModuleTransferable.self)
        }
    }

    @ViewBuilder private var detailEditorView: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.adventureEditModel.selectionDice)
            .onChange(of: root.editController.adventureEditModel.selectionDice.selection) {
                withAnimation { root.editController.add(diceId: root.editController.adventureEditModel.selectionDice.itemId, itemId: model.id) }
            }
            .onChange(of: model.diceId, initial: true) {
                withAnimation { root.editController.adventureEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil) }
            }

        root.photoRoot.viewController.dropSelectionView(model: root.editController.adventureEditModel.selectionPhoto)
            .onChange(of: root.editController.adventureEditModel.selectionPhoto.itemId) {
                withAnimation { root.editController.add(photoId: root.editController.adventureEditModel.selectionPhoto.itemId, itemId: model.id) }
            }
            .onChange(of: model.photoId, initial: true) {
                withAnimation { root.editController.adventureEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil) }
            }

        SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, model: model, module: root.config.module, headerTitle: String(localized: "Sections", bundle: .module).localizedString, linkTypes: LinkAdventureModuleTransferable.self)
    }
}
