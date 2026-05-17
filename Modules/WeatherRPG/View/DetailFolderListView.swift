// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct DetailFolderListView: View, Equatable {
    private let rootStorage: WeatherRootModel
    let model: WeatherModel
    @Binding var animate: Bool
    private let navigationModel: ModuleNavigationModel
    
    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    
    @State private var detailRoute: WeatherDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false
    @State private var detailFolderListController: FolderListController
    
    init(root: WeatherRootModel, model: WeatherModel, animate: Binding<Bool>) {
        self.rootStorage = root
        self.model = model
        self._animate = animate
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
                        detailRoute = WeatherDetailRoute.folder(subItemId)
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
                        WeatherDetailRoute.folderInline(lastFolderId)
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
            listController: listController,
            animate: $animate
        )
    }
}

private struct DetailFolderContentView: View {
    let root: WeatherRootModel
    let model: WeatherModel
    let listController: any FolderListControllable
    @Binding var animate: Bool
    
    var body: some View {
        ItemDetailRootView(
            root: root.rootController,
            detailListController: listController,
            selectedModel: model,
            configuration: .init(hasEntryEditor: false),
            linkTypes: EmptyLinkTransferable.self) {
                WeatherEditor(model: model)
            }
            .safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
                OverlayViewer(model: model, animate: $animate)
                    .opacity(0)
            }
            .overlay(alignment: .bottom) {
                OverlayViewer(model: model, animate: $animate)
                    .allowsHitTesting(false)
            }
            .overlay {
                if root.openFileWindowModel.showItem {
                    root.viewController.viewer(root: root, itemId: root.openFileWindowModel.itemId, configuration: ViewerConfiguration(closeButton: true)) {
                        root.openFileWindowModel.showItem = false
                    }
                }
            }
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
