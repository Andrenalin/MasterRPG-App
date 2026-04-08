// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: MapRootModel
    let model: MapModel

    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: MapDetailRoute?
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
                        detailRoute = MapDetailRoute.folder(subItemId)
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
                        MapDetailRoute.folderInline(lastFolderId)
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
            .onChange(of: model.id, initial: true) {
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
            EntryEditorView(editController: root.editController, model: model, linkTypes: LinkMapModuleTransferable.self)
        }
    }

    @ViewBuilder private var detailEditorView: some View {
        root.photoRoot.viewController.dropSelectionView(model: root.editController.mapEditModel.selectionPhoto)
            .onChange(of: root.editController.mapEditModel.selectionPhoto.itemId) {
                withAnimation { root.editController.add(photoId: root.editController.mapEditModel.selectionPhoto.itemId, itemId: model.id) }
            }
            .onChange(of: model.photoId, initial: true) {
                withAnimation { root.editController.mapEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil) }
            }

        DisplayConfigEditor(model: model)

        SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, model: model, module: root.config.module, headerTitle: String(localized: "Rooms", bundle: .module).localizedString, linkTypes: LinkMapModuleTransferable.self)
    }
}
