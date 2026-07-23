// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: GeneratorRootModel
    let model: GeneratorModel

    @Environment(\.navigator) private var navigator

    @State private var detailFolderListController: FolderListController
    @State private var selection = ItemSelectionModel()

    init(root: GeneratorRootModel, model: GeneratorModel) {
        self.root = root
        self.model = model
        let listController = root.folderListControllable
        self._detailFolderListController = State(wrappedValue: listController as! FolderListController)
    }

    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: GeneratorDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
            .onChange(of: model.id, initial: true) {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
            }
    }

    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(
            root: root.rootController,
            detailListController: listController,
            selectedModel: model,
            configuration: .init(),
            linkTypes: EmptyLinkTransferable.self
        ) {
            Text("Add a reference character", bundle: .module)
            detailEditorView(model: model)
        }
        .overlay {
            if root.openFileWindowModel.showItem {
                root.viewController.viewer(
                    root: root,
                    itemId: root.openFileWindowModel.itemId,
                    configuration: ViewerConfiguration(closeButton: true)
                ) {
                    root.openFileWindowModel.showItem = false
                }
            }
        }
        .moduleTint(root.configurable.module)
        .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
            UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
#if !os(tvOS)
            root.addSiriContext(to: activity, itemId: model.id)
#endif
        }
#if !os(tvOS)
        .task(id: model.id) {
            await root.donateSiriViewingIntent(for: model.id)
        }
#endif
    }

    @ViewBuilder
    func detailEditorView(model: GeneratorModel) -> some View {
        @Bindable var model = model
        Picker(selection: $model.genType) {
            ForEach(GeneratorModel.GenType.allCases) { genType in
                Text(genType.title)
                    .tag(genType)
            }
        } label: {
            Text("Generation Type", bundle: .module)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(GeneratorRootModel.self) var root

    if let model = root.itemController.itemSync(for: GeneratorModel.previewId) {
        DetailListView(root: root, model: model)
    }
}
