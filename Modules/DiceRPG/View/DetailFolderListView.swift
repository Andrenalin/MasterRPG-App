// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailFolderListView: View, Equatable {
    private let rootStorage: DiceRootModel
    let model: DiceModel
    private let navigationModel: ModuleNavigationModel

    @Environment(\.navigator) private var navigator
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var detailRoute: DiceDetailRoute?
    @State private var lastFolderId: UUID?
    @State private var showFolderDetail: Bool = false
    @State private var detailFolderListController: FolderListController

    init(root: DiceRootModel, model: DiceModel) {
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
    let rootStorage: DiceRootModel
    let model: DiceModel
    let detailFolderListController: FolderListController

    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @State private var detailRoute: DiceDetailRoute?

    var body: some View {
        ItemDetailRootView(
            root: rootStorage.rootController,
            detailListController: detailFolderListController,
            selectedModel: model,
            configuration: .init(editorAsBackground: false, hasOverlay: true, hasEntryEditor: false),
            linkTypes: EmptyLinkTransferable.self
        ) {
            DetailEditorView(model: model)
        } overlay: {
            DiceOverlayView(model: model)
        }
        .applyIf(appSizeModel.mode == .compact) {
            $0.navigate(to: $detailRoute)
                .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                    guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                    detailRoute = DiceDetailRoute.folder(subItemId)
                }
                .onChange(of: detailRoute) { oldRoute, newRoute in
                    guard detailRoute == nil else { return }
                    detailFolderListController.listModel.resetListModel()
                }
        }
    }
}

private struct DetailEditorView: View {
    let model: DiceModel

    var body: some View {
        DiceEditor(model: model)
        DiceOptionEditor(model: model)
        CoupEditor(model: model)
        FumbleEditor(model: model)
        RerollEditor(model: model)
        SpecialOptionEditor(model: model)
    }
}

private struct DiceOverlayView: View {
    let model: DiceModel

    var body: some View {
        GlassEffectContainerView {
            DiceViewer(model: model, isEditor: false)
                .padding()
#if !os(visionOS)
                .glassEffect(.clear)
#endif
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
                    DiceDetailRoute.folderInline(lastFolderId)
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
