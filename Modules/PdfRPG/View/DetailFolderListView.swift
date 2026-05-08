// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View {
    let root: PdfRootModel
    let model: PdfModel

    @Environment(OpenFileWindowModel.self) private var openFileWindowModel
    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: PdfDetailRoute?
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
                        detailRoute = PdfDetailRoute.folder(subItemId)
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
                        PdfDetailRoute.folderInline(lastFolderId)
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
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(
            detailListController: listController,
            selectedModel: model,
            configuration: .init(editorAsBackground: false, hasOverlay: false)
        ) {
            EmptyView()
        } editor: {
            fileAndPlayerView(model: model)

            SheetFirstRootEditorView(root: root.rootController, linkControllable: root.linkControllable, editorModel: root.editController.sheetEditorModel, model: model, module: root.config.module, headerTitle: String(localized: "Bookmarks", bundle: .module).localizedString, linkTypes: LinkPdfModuleTransferable.self)
                .id(model.id)
        } overlay: {
            EmptyView()
        } entryEditor: {
            EntryEditorView(rootManager: root.linkControllable.rootManager, editorModel: root.editController.sheetEditorModel, linkTypes: LinkPdfModuleTransferable.self)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.viewer(root: root, itemId: openFileWindowModel.itemId, entryId: nil, configuration: ViewerConfiguration(closeButton: true, canBookmark: true), onTextExtracted: nil, dismissAction: {
                    openFileWindowModel.showItem = false
                })
            }
        }
    }
    
    func fileAndPlayerView(model: PdfModel) -> some View {
        VStack(spacing: 12) {
            HStack {
                HStack {
                    FileImporterView(editControllable: root.editController, fileTypes: root.editController.fileUrlDataController?.fileTypes ?? [], itemId: model.id)
                    
                    Text(model.url?.path(percentEncoded: false) ?? "No file is set")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                }
                .opacity(model.specialCategory ? 0 : 1)
            }
        }
        .padding()
    }
}
