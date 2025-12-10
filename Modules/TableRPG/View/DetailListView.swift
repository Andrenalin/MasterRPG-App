// @copyright André Trettin

import CoreRPG

import DiceRPG
import SwiftUI

struct DetailListView: View {
    init(root: TableRootModel, model: TableModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: TableRootModel
    let model: TableModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.table.viewerWindowId, canShow: true, route: { DetailRoute.viewer($0) })
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: TableDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedId: model.id, editorAsBackground: false) {
        } editor: {
            detailEditorView
        } inspector: {
            EditorLinkView()
        } entryEditor: {
            EntryEditorView(editController: root.editController)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .toolbar {
            toolbarContent
        }
        .environment(openFileWindowModel)
        .environment(root.folderListController.cacheListItemModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(root.module.tint)
        .accentColor(root.module.tint)
    }
}

private extension DetailListView {
    @ViewBuilder var detailEditorView: some View {
        root.diceRoot.viewController.dropChooseView(model: root.editController.tableEditModel.selectionDice)
            .onChange(of: root.editController.tableEditModel.selectionDice.selection) {
                withAnimation { root.editController.add(diceId: root.editController.tableEditModel.selectionDice.itemId, model: model) }
            }
            .onChange(of: model.diceId, initial: true) {
                withAnimation { root.editController.tableEditModel.selectionDice.resetSelection(itemId: model.diceId) }
            }
        
        EntryListView(editController: root.editController, linkTypes: LinkTableModuleTransferable.self, headerTitle: "Entries")
            .onChange(of: root.editController.tableEditModel.addLinkDice.selection) {
                guard let entryId = root.editController.editorModel.currentEntryId else { return }
                let selection = root.editController.tableEditModel.addLinkDice.selection
                for link in selection {
                    withAnimation { root.editController.add(link: "Dice - Link", module: .dice, itemId: link.itemId, entryId: link.entryId, destinationEntryId: entryId) }

                }
            }
    }

    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryActionAll) {
            ControlGroup {
                Button {
                    navigator.navigate(to: EditorRoute.quickEditor, method: .cover)
                } label: {
                    Label {
                        Text("Quick Editor", bundle: .module)
                    } icon: {
                        Image(systemName: "table.badge.more")
                    }
                }
                
                Button {
                    withAnimation {
                        let entryId = root.editController.addNewEntry()
                        root.editController.editorModel.currentEntryId = entryId
                        Task { @MainActor in
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
            }
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            Button {
                withAnimation {
                    navigator.navigate(to: EditorRoute.addLink(.dice), method: .managedSheet)
                }
            } label: {
                Label {
                    Text("Link", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.dice.icon)
                }
            }
            
            Button {
                withAnimation {
                    navigator.navigate(to: EditorRoute.addLink(.table), method: .managedSheet)
                }
            } label: {
                Label {
                    Text("Link", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.table.icon)
                }
            }
        }
        #endif
    }
    
    private func addLinkButton(module: NetworkModules) -> some View {
        Button {
            withAnimation {
                navigator.navigate(to: EditorRoute.addLink(module), method: .managedSheet)
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

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    @Previewable @Environment(ListModel.self) var listModel
    
    if listModel.selectedItem == nil {
        Text("Hello")
            .onAppear {
                let id = root.itemController.itemDataModel.items.first ?? TableModel.previewId
                root.editController.model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? TableModel.previewId)
                listModel.selectedItem = ItemRowTreeModel(itemId: id, typeId: .space)
            }
    } else {
        ManagedNavigationStack {
            DetailListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? TableModel.previewId))
                .preferredColorScheme(.dark)
        }
    }
}
