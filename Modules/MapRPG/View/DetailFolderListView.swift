// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailFolderListView: View, Equatable {
    // Store root temporarily for initialization, but don't access in body
    private let rootStorage: MapRootModel
    let model: MapModel

    // Extract only what we need for body evaluation
    private let navigationModel: ModuleNavigationModel

    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: MapDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false
    @State private var detailFolderListController: FolderListController

    init(root: MapRootModel, model: MapModel) {
        self.rootStorage = root
        self.model = model
        self.navigationModel = root.navigationModel

        // Get or create the list model
        let listModel = root.navigationModel.folderModels[model.id]
        let allListModel = listModel ?? root.folderListController.copyModel(parentModel: model)
        if listModel == nil {
            root.navigationModel.folderModels[model.id] = allListModel
        }

        let controller = root.folderListController.copy(listModel: allListModel) as! FolderListController
        self._detailFolderListController = State(initialValue: controller)

        print("🔄 DetailFolderListView.detailFolderListController created for model: \(model.name)")
    }

    // Equatable conformance: only recreate if model.id changes
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
                        detailRoute = MapDetailRoute.folder(subItemId)
                    }
                    .onChange(of: detailRoute) { oldRoute, newRoute in
                        guard detailRoute == nil else { return }
                        detailFolderListController.listModel.resetListModel()
                    }
            }
            .applyIf(appSizeModel.mode == .regular) {
                $0.background {
                    // Isolate folderItems observation to prevent parent re-renders
                    FolderItemsObserver(
                        navigationModel: navigationModel,
                        lastFolderId: $lastFolderId,
                        showFolderDetail: $showFolderDetail
                    )
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
                rootStorage.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: rootStorage.config.module))
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

// MARK: - Separate Content View to Reduce Observable Dependencies

private struct DetailFolderContentView: View {
    let root: MapRootModel
    let model: MapModel
    let listController: any FolderListControllable

    var body: some View {
        ItemDetailRootView(
            root: root.rootController,
            detailListController: listController,
            selectedModel: model,
            openFileWindowModel: root.openFileWindowModel,
            configuration: .init(editorAsBackground: false, hasOverlay: false)
        ) {
            DetailEditorView(root: root, model: model)
        } overlay: {
            EmptyView()
        } entryEditor: {
            EntryEditorView(rootManager: root.linkControllable.rootManager, editorModel: root.editController.sheetEditorModel, linkTypes: LinkMapModuleTransferable.self)
        }
    }
}

// MARK: - Detail Editor View (Isolated from Parent)

private struct DetailEditorView: View {
    let root: MapRootModel
    let model: MapModel

    var body: some View {
        root.photoRoot.viewController.dropSelectionView(model: root.editController.mapEditModel.selectionPhoto)
            .onChange(of: root.editController.mapEditModel.selectionPhoto.itemId) {
                withAnimation { root.editController.add(photoId: root.editController.mapEditModel.selectionPhoto.itemId, itemId: model.id) }
            }
            .task(id: model.photoId) {
                root.editController.mapEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil)
            }

        DisplayConfigEditor(model: model)

        SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, editorModel: root.editController.sheetEditorModel, model: model, module: root.config.module, headerTitle: String(localized: "Rooms", bundle: .module).localizedString, linkTypes: LinkMapModuleTransferable.self)
            .id(model.id)
    }
}

// MARK: - Folder Items Observer (Isolated Observable Dependency)

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
