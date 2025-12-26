// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailRootView: View {
    let root: CharacterRootModel
    let model: ValueModel
    
    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

struct DetailListView: View {
    init(root: CharacterRootModel, model: ValueModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
        let sheetModel = SheetController(itemController: root.itemController, linkController: root.linkController).sheet(for: model.id)
        self.tableSheetModel = TableSheetModel(linkControllable: root.rootControllable.linkControllable, sheetModel: sheetModel, searchText: "")
    }
    
    let root: CharacterRootModel
    let model: ValueModel
    let tableSheetModel: TableSheetModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.value.viewerWindowId, canShow: true, route: { DetailRoute.viewer($0) })
    
    @State private var showViewer: Bool = false
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: CharacterDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
            .onAppear {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: .value))
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: false) {
        } editor: {
            detailEditorView
        } inspector: {
            EditorLinkView(root: root.rootController, editorLinkModel: root.editorLinkModel)
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
        .tint(root.configurable.module.tint)
        .accentColor(root.configurable.module.tint)
    }
}

private extension DetailListView {
    @ViewBuilder var detailEditorView: some View {
        root.photoRoot.viewController.dropSelectionView(model: root.editController.valueEditModel.selectionPhoto)
            .onChange(of: root.editController.valueEditModel.selectionPhoto.itemId) {
                withAnimation { root.editController.add(photoId: root.editController.valueEditModel.selectionPhoto.itemId) }
            }
            .onChange(of: model.photoId, initial: true) {
                withAnimation { root.editController.valueEditModel.selectionPhoto.resetSelection(itemId: model.photoId) }
            }

        Toggle(isOn: $showViewer) {
            Text("Viewer Style")
        }
        
        if showViewer {
            Section {
                SheetView(root: root.rootController, model: tableSheetModel)
            } header: {
                Text("Values")
            }
        } else {
            EntryListView(editController: root.editController, linkTypes: LinkCharacterModuleTransferable.self, headerTitle: "Values")
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
            ForEach(root.editorLinkModel.modulesRow, id: \.self) { module in
                addLinkButton(module: module)
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
    @Previewable @Environment(CharacterRootModel.self) var root
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? ValueModel.previewId))
            .preferredColorScheme(.dark)
    }
}
