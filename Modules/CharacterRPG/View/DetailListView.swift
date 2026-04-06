// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailListView: View {
    let root: CharacterRootModel
    let model: ValueModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var openFileWindowModel = OpenFileWindowModel()
    
    var body: some View {
        DetailFolderListView(root: root, model: model)
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
                            root.editController.editorModel.currentEntryId = entryId
                            Task {
                                try? await Task.sleep(for: .seconds(0.25))
                                root.editController.editorModel.scrollEntryId = entryId
                            }
                        }
                    } label: {
                        Label {
                            Text("Add new Entry", bundle: .module)
                        } icon: {
                            Image(systemName: "note.text.badge.plus")
                        }
                    }
                    
                    Button {
                        root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
                        let itemId = model.id
                        Task {
                            let entryId = await root.editController.addNewGroup(itemId: itemId)
                            withAnimation {
                                root.editController.editorModel.currentEntryId = entryId
                            }
                        }
                    } label: {
                        Label {
                            Text("Add new Group", bundle: .module)
                        } icon: {
                            Image(systemName: "plus.square.fill.on.square.fill")
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
