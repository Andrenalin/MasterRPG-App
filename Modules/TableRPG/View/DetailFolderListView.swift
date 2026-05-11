// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DetailFolderListView: View, Equatable {
    private let rootStorage: TableRootModel
    let model: TableModel
    private let navigationModel: ModuleNavigationModel

    @Environment(OpenFileWindowModel.self) private var openFileWindowModel
    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: TableDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false
    @State private var detailFolderListController: FolderListController

    init(root: TableRootModel, model: TableModel) {
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
            .onAppear {
                rootStorage.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: rootStorage.config.module))
            }
            .applyIf(appSizeModel.mode == .compact) {
                $0.navigate(to: $detailRoute)
                    .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                        guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                        detailRoute = TableDetailRoute.folder(subItemId)
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
                        TableDetailRoute.folderInline(lastFolderId)
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
    let root: TableRootModel
    let model: TableModel
    let listController: any FolderListControllable

    @Environment(OpenFileWindowModel.self) private var openFileWindowModel

    var body: some View {
        ItemDetailRootView(
            detailListController: listController,
            selectedModel: model,
            configuration: .init(editorAsBackground: false, hasOverlay: false)
        ) {
            EmptyView()
        } editor: {
            DetailEditorView(root: root, model: model)
        } overlay: {
            EmptyView()
        } entryEditor: {
            EntryEditorView(rootManager: root.linkControllable.rootManager, editorModel: root.editController.sheetEditorModel, linkTypes: LinkTableModuleTransferable.self)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.viewer(root: root, itemId: openFileWindowModel.itemId, configuration: ViewerConfiguration(closeButton: true)) {
                    openFileWindowModel.showItem = false
                }
            }
        }
    }
}

private struct DetailEditorView: View {
    let root: TableRootModel
    let model: TableModel

    var body: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.tableEditModel.selectionDice)
            .onChange(of: root.editController.tableEditModel.selectionDice.selection) {
                withAnimation { root.editController.add(diceId: root.editController.tableEditModel.selectionDice.itemId, itemId: model.id) }
            }
            .task(id: model.diceId) {
                root.editController.tableEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }

        SheetFirstRootEditorView(root: root.rootController, linkControllable: root.linkControllable, editorModel: root.editController.sheetEditorModel, model: model, module: root.config.module, headerTitle: String(localized: "Entries", bundle: .module).localizedString, linkTypes: LinkTableModuleTransferable.self)
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
