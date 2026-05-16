// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View, Equatable {
    private let rootStorage: AudioRootModel
    let model: AudioModel
    private let navigationModel: ModuleNavigationModel

    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: AudioDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false
    @State private var detailFolderListController: FolderListController

    init(root: AudioRootModel, model: AudioModel) {
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
    let rootStorage: AudioRootModel
    let model: AudioModel
    let detailFolderListController: FolderListController

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @State private var detailRoute: AudioDetailRoute?

    var body: some View {
        ItemDetailRootView(
            root: rootStorage.rootController,
            detailListController: detailFolderListController,
            selectedModel: model,
            configuration: .init(editorAsBackground: false, hasOverlay: true)
        ) {
            EmptyView()
        } editor: {
            DetailEditorView(rootStorage: rootStorage, model: model)
        } overlay: {
            AudioPlayerBarView()
                .padding()
        } entryEditor: {
            EmptyView()
        }
        .applyIf(appSizeModel.mode == .compact) {
            $0.navigate(to: $detailRoute)
                .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                    guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                    detailRoute = AudioDetailRoute.folder(subItemId)
                }
                .onChange(of: detailRoute) { oldRoute, newRoute in
                    guard detailRoute == nil else { return }
                    detailFolderListController.listModel.resetListModel()
                }
        }
    }
}

private struct DetailEditorView: View {
    let rootStorage: AudioRootModel
    let model: AudioModel

    var body: some View {
        HStack {
            HStack {
                FileImporterView(
                    editControllable: rootStorage.editController,
                    fileTypes: rootStorage.editController.fileUrlDataController?.fileTypes ?? [],
                    itemId: model.id
                )

                Text(model.url?.path(percentEncoded: false) ?? "No file is set")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(model.specialCategory ? 0 : 1)
        }
        .padding()
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
                    AudioDetailRoute.folderInline(lastFolderId)
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
