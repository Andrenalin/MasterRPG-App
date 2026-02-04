// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG
import PhotoRPG

struct DetailRootView: View {
    let root: AdventureRootModel
    let model: AdventureModel
    
    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(folderListControllable: root.folderListController)
    }
}

struct DetailListView: View {
    init(root: AdventureRootModel, model: AdventureModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: AdventureRootModel
    let model: AdventureModel
    
    @Environment(\.navigator) private var navigator
#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.adventure.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: AdventureDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
            .onAppear {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: false) {
        } editor: {
            detailEditorView
        } inspector: {
            EditorLinkView(root: root.rootController, model: model, editorLinkModel: root.editorLinkModel)
        } entryEditor: {
            EntryEditorView(editController: root.editController, model: model)
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
        root.photoRoot.viewController.dropSelectionView(model: root.editController.adventureEditModel.selectionPhoto)
            .onChange(of: root.editController.adventureEditModel.selectionPhoto.itemId) {
                withAnimation { root.editController.add(photoId: root.editController.adventureEditModel.selectionPhoto.itemId, itemId: model.id) }
            }
            .onChange(of: model.photoId, initial: true) {
                withAnimation { root.editController.adventureEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil) }
            }
        
        SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, model: model, module: root.config.module, headerTitle: String(localized: "Sections").localizedString, linkTypes: LinkAdventureModuleTransferable.self)
    }
    
    @ToolbarContentBuilder var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryActionAll) {
            if !openFileWindowModel.showItem {
                ControlGroup {
                    Button {
                        navigator.navigate(to: EditorRoute.quickEditor(model.id), method: .cover)
                    } label: {
                        Label {
                            Text("Quick Editor", bundle: .module)
                        } icon: {
                            Image(systemName: "table.badge.more")
                        }
                    }
                    
                    Button {
                        withAnimation {
                            let entryId = root.editController.addNewEntry(itemId: model.id)
                            root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, entryId: entryId, typeId: root.config.module))
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

#if !os(tvOS)
                    Button {
#if os(visionOS) || os(macOS)
                    openWindow(id: WindowIdentifier.generateAdventure.rawValue)
#else
                    navigator.navigate(to: EditorRoute.generator(model.id), method: .managedSheet)
#endif
                    } label: {
                        Label {
                            Text("AI Assistant", bundle: .module)
                        } icon: {
                            Image(systemName: NetworkModules.generator.icon)
                        }
                    }
#endif
                }
            }
        }
#if os(iOS)
        ToolbarItemGroup(placement: .keyboard) {
            ForEach(root.editorLinkModel.firstRow, id: \.self) { module in
                addLinkButton(module: module)
            }
        }
#endif
    }
    
    private func addLinkButton(module: NetworkModules) -> some View {
        Button {
            withAnimation {
                navigator.navigate(to: EditorRoute.addLink(ItemRowModel(itemId: model.id, typeId: module)), method: .managedSheet)
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
    @Previewable @Environment(AdventureRootModel.self) var root

    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AdventureModel.previewId))
            .preferredColorScheme(.dark)
    }
    .setAppSizeMode()
}
