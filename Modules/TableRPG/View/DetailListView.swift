// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

struct DetailListView: View, Equatable {
    let root: TableRootModel
    let model: TableModel

    @Environment(\.navigator) private var navigator

    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.table.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }

    static func == (lhs: DetailListView, rhs: DetailListView) -> Bool {
        lhs.model.id == rhs.model.id
    }

    var body: some View {
        DetailFolderListView(root: root, model: model)
            .equatable()
            .toolbar {
                toolbarContent
            }
            .environment(openFileWindowModel)
            .environment(root.folderListController.cacheListItemModel)
            .environment(root.listDisplayModel)
            .environment(root.searchModel)
            .environment(root.rootController)
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
            .userActivity(UserActivity.bundleIdentifierType, isActive: true) { activity in
                UserActivity.addPayLoad(for: activity, title: model.name, module: root.config.module, itemId: model.id)
            }
    }
}

private extension DetailListView {
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryActionAll) {
            if !model.specialCategory {
                ControlGroup {
                    Button {
                        navigator.navigate(to: EditorRoute.quickEditor(model.id))
                    } label: {
                        Label {
                            Text("Quick Editor", bundle: .module)
                        } icon: {
                            Image(systemName: "table.badge.more")
                        }
                    }
                    
                    Button {
                        withAnimation {
                            root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
                            let entryId = root.editController.addNewEntry(itemId: model.id)
                            root.editController.sheetEditorModel.entryId = entryId
                            Task {
                                try? await Task.sleep(for: .seconds(0.25))
                                root.editController.sheetEditorModel.scrollEntryId = entryId
                            }
                        }
                    } label: {
                        Label {
                            Text("Add new Entry", bundle: .module)
                        } icon: {
                            Image(systemName: "note.text.badge.plus")
                        }
                    }
                }
            }
        }
#if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            ForEach(root.editorLinkModel.modulesRow, id: \.self) { module in
                addLinkButton(module: module)
            }
        }
#endif
    }
    
    private func addLinkButton(module: NetworkModules) -> some View {
        Button {
            withAnimation {
                navigator.navigate(to: EditorRoute.addLink(ItemRowModel(itemId: model.id, typeId: module)))
            }
        } label: {
            Label {
                Text("Link", bundle: .module)
            } icon: {
                Image(systemName: module.icon)
            }
        }
    }
}
