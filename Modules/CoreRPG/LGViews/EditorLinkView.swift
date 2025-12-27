// @copyright André Trettin

import SwiftUI

public struct EditorLinkView: View {
    public init(root: ItemRootController, editorLinkModel: EditorLinkModel, selectedModule: NetworkModules? = nil, selectedEntryId: UUID? = nil) {
        self.root = root
        self.editorLinkModel = editorLinkModel
        self.selectedEntryId = selectedEntryId
        editorLinkModel.preselectedModule = selectedModule
    }
    
    let root: ItemRootController
    let editorLinkModel: EditorLinkModel
    let selectedEntryId: UUID?
    
    public var body: some View {
        VStack {
            pickerAll
            
            ZStack {
                ForEach(editorLinkModel.modulesRow, id: \.self) { module in
                    ManagedNavigationStack(name: "EditorLink") {
                        linkLinkView(module: module)
                    }
                    .opacity(editorLinkModel.selection == module ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .applyIf(selectionMode) {
            $0
                .toolbarItemListModifier(root: root, listControllable: editorLinkModel.folderListController, parentModel: nil, modal: true) {
                    guard let editControllable = root.editControllable as? (any EntryDataEditable) else { return }
                    editorLinkModel.addLinkAndReset(editController: editControllable, destinationEntryId: selectedEntryId)
                }
                .searchItemList(listControllable: editorLinkModel.folderListController)
        }
        .environment(editorLinkModel.folderListController.cacheListItemModel)
        .onChange(of: editorLinkModel.selectionFirstRow) {
            guard let selectionFirstRow = editorLinkModel.selectionFirstRow else { return }
            withAnimation {
                editorLinkModel.update(selection: selectionFirstRow)
            }
        }
        .onChange(of: editorLinkModel.selectionSecondRow) {
            guard let selectionSecondRow = editorLinkModel.selectionSecondRow else { return }
            withAnimation {
                editorLinkModel.update(selection: selectionSecondRow)
            }
        }
        .onChange(of: editorLinkModel.selection, initial: true) {
            editorLinkModel.updateListController()
        }
        .onChange(of: editorLinkModel.folderListController.listDisplayModel.displayMode) {
            editorLinkModel.update()
        }
        .onChange(of: editorLinkModel.folderListController.listDisplayModel.listMode) {
            editorLinkModel.update()
        }
        .onChange(of: editorLinkModel.folderListController.searchModel.searchText) {
            editorLinkModel.update()
        }
        .onAppear {
            guard let preselectedModule = editorLinkModel.preselectedModule else { return }
            withAnimation { editorLinkModel.update(selection: preselectedModule) }
        }
        .navigationTitle(editorLinkModel.selection.title)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private extension EditorLinkView {
    var selectionMode: Bool {
        selectedEntryId != nil
    }
    
    @ViewBuilder func linkLinkView(module: NetworkModules) -> some View {
        if let itemRootController = editorLinkModel.rootManager.itemRootController(for: module) {
            itemRootController.viewControllable.linkListView(rootController: itemRootController, type: selectionMode ? .selectionInline : .inspector, itemSelectionModel: editorLinkModel.selectionModel(for: module))
        }
    }
    
    @ViewBuilder var pickerAll: some View {
        @Bindable var editorLinkModel = editorLinkModel
        
        pickerRow(selectionRow: $editorLinkModel.selectionFirstRow, modules: editorLinkModel.firstRow)
        if !editorLinkModel.secondRow.isEmpty {
            pickerRow(selectionRow: $editorLinkModel.selectionSecondRow, modules: editorLinkModel.secondRow)
        }
    }
    
    func pickerRow(selectionRow: Binding<NetworkModules?>, modules: [NetworkModules]) -> some View {
        Picker(selection: selectionRow) {
            ForEach(modules, id: \.self) { module in
                buttonPicker(module: module)
            }
        } label: {
            Text("Module selection", bundle: .module)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    func buttonPicker(module: NetworkModules) -> some View {
        Image(systemName: module.icon)
            .tag(module)
    }
}
