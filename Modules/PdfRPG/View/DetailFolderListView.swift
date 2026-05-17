// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View, Equatable {
    private let rootStorage: PdfRootModel
    let model: PdfModel
    private let navigationModel: ModuleNavigationModel

    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: PdfDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false
    @State private var detailFolderListController: FolderListController

    init(root: PdfRootModel, model: PdfModel) {
        self.rootStorage = root
        self.model = model
        self.navigationModel = root.navigationModel

        let listModel = root.navigationModel.folderModels[model.id]
        let allListModel = listModel ?? root.folderListController.copyModel(parentModel: model)
        if listModel == nil {
            root.navigationModel.folderModels[model.id] = allListModel
        }

        let controller = root.folderListController.copy(listModel: allListModel) as! FolderListController
        self._detailFolderListController = State(initialValue: controller)

        print("🔄 DetailFolderListView.detailFolderListController created for model: \(model.name)")
    }

    static func == (lhs: DetailFolderListView, rhs: DetailFolderListView) -> Bool {
        lhs.model.id == rhs.model.id
    }
    
    var body: some View {
        let _ = Self._printChanges()

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
                $0.background {
                    FolderItemsObserver(
                        navigationModel: navigationModel,
                        lastFolderId: $lastFolderId,
                        showFolderDetail: $showFolderDetail
                    )
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
    
    @ViewBuilder
    func content(listController: any FolderListControllable) -> some View {
        let _ = print("🔍 DetailFolderListView.content() called for model: \(model.name)")
        DetailFolderContentView(
            root: rootStorage,
            model: model,
            listController: listController
        )
    }
}

private struct DetailFolderContentView: View {
    let root: PdfRootModel
    let model: PdfModel
    let listController: any FolderListControllable

    var body: some View {
        ItemDetailRootView(
            root: root.rootController,
            detailListController: listController,
            selectedModel: model,
            configuration: .init(editorAsBackground: false, hasOverlay: false),
            linkTypes: LinkPdfModuleTransferable.self
        ) {
            DetailEditorView(root: root, model: model)
        } overlay: {
            EmptyView()
        }
        .overlay {
            if root.openFileWindowModel.showItem {
                root.viewController.viewer(root: root, itemId: root.openFileWindowModel.itemId, entryId: nil, configuration: ViewerConfiguration(closeButton: true, canBookmark: true), onTextExtracted: nil, dismissAction: {
                    root.openFileWindowModel.showItem = false
                })
            }
        }
    }
}

private struct DetailEditorView: View {
    let root: PdfRootModel
    let model: PdfModel

    var body: some View {
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

        SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, editorModel: root.editController.sheetEditorModel, model: model, module: root.config.module, headerTitle: String(localized: "Bookmarks", bundle: .module).localizedString, linkTypes: LinkPdfModuleTransferable.self)
            .id(model.id)
    }
}

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
