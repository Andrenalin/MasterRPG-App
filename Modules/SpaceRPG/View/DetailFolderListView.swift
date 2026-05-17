// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View, Equatable {
    private let rootStorage: SpaceRootModel
    let model: SpaceModel
    private let navigationModel: ModuleNavigationModel

    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: SpaceDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false
    @State private var detailFolderListController: FolderListController

    init(root: SpaceRootModel, model: SpaceModel) {
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

        DetailFolderContentView(
            rootStorage: rootStorage,
            model: model,
            detailFolderListController: detailFolderListController
        )
        .background {
            FolderItemsObserver(
                navigationModel: navigationModel,
                appSizeModel: appSizeModel,
                lastFolderId: $lastFolderId,
                showFolderDetail: $showFolderDetail,
                detailFolderListController: detailFolderListController
            )
        }
    }
}

private struct DetailFolderContentView: View {
    let rootStorage: SpaceRootModel
    let model: SpaceModel
    let detailFolderListController: FolderListController

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @State private var detailRoute: SpaceDetailRoute?

    var body: some View {
        ItemDetailRootView(
            root: rootStorage.rootController,
            detailListController: detailFolderListController,
            selectedModel: model,
            configuration: .init(editorAsBackground: true, hasOverlay: false, hasEntryEditor: false),
            linkTypes: EmptyLinkTransferable.self
        ) {
            ViewerRootView(model: model, configuration: ViewerConfiguration(closeButton: false, addToolbar: false, isGame: false))
        } overlay: {
            EmptyView()
        }
        .overlay {
            if rootStorage.openFileWindowModel.showItem {
                rootStorage.viewController.viewer(root: rootStorage, itemId: rootStorage.openFileWindowModel.itemId, configuration: ViewerConfiguration(closeButton: true)) {
                    rootStorage.openFileWindowModel.showItem = false
                }
            }
        }
        .applyIf(appSizeModel.mode == .compact) {
            $0.navigate(to: $detailRoute)
                .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                    guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                    detailRoute = SpaceDetailRoute.folder(subItemId)
                }
                .onChange(of: detailRoute) { oldRoute, newRoute in
                    guard detailRoute == nil else { return }
                    detailFolderListController.listModel.resetListModel()
                }
        }
    }
}

private struct FolderItemsObserver: View {
    let navigationModel: ModuleNavigationModel
    let appSizeModel: AppWindowSizeModel
    @Binding var lastFolderId: UUID?
    @Binding var showFolderDetail: Bool
    let detailFolderListController: FolderListController

    var body: some View {
        Color.clear
            .applyIf(appSizeModel.mode == .regular) {
                $0.onChange(of: navigationModel.folderItems) {
                    guard lastFolderId == nil, let subItemId = navigationModel.folderItems.last else { return }
                    lastFolderId = subItemId
                    withAnimation {
                        showFolderDetail = true
                    }
                }
            }
            .overlay {
                if appSizeModel.mode == .regular, showFolderDetail, let lastFolderId {
                    SpaceDetailRoute.folderInline(lastFolderId)
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
