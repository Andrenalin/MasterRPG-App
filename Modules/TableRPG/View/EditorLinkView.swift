// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI


//struct EditorLinkView: View {
//    init(root: TableRootModel, selectedModule: NetworkModules = .table, selectedEntryId: UUID? = nil) {
//        self.root = root
//        self.selectedEntryId = selectedEntryId
//        root.editorLinkModel.selection = selectedModule
//    }
//    
//    let root: TableRootModel
//    let selectedEntryId: UUID?
//        
//    var body: some View {
//        ManagedNavigationStack(name: "TableEditorLink") {
//            VStack {
//                pickerRow(modules: root.editorLinkModel.firstRow)
//                
//                ZStack {
//                    root.diceRoot.viewController.linkListView(type: selectionMode ? .selectionInline : .inspector, itemSelectionModel: root.editorLinkModel.diceSelectionModel)
//                        .opacity(root.editorLinkModel.selection == .dice ? 1 : 0)
//                    root.viewController.linkListView(type: selectionMode ? .selectionInline : .inspector, itemSelectionModel: root.editorLinkModel.tableSelectionModel)
//                        .opacity(root.editorLinkModel.selection == .table ? 1 : 0)
//                }
//            }
//            .toolbarItemListModifier(root: root, listControllable: root.editorLinkModel.folderListController, parentModel: nil, modal: true) {
//                root.editorLinkModel.addLinkAndReset(editController: root.editController, destinationEntryId: selectedEntryId)
//            }
//            .searchItemList(listControllable: root.editorLinkModel.folderListController)
//            .environment(root.editorLinkModel.folderListController.cacheListItemModel)
//            .onChange(of: root.editorLinkModel.selection, initial: true) {
//                root.editorLinkModel.updateListController()
//            }
//            .onChange(of: root.editorLinkModel.folderListController.listDisplayModel.displayMode) {
//                root.editorLinkModel.update()
//            }
//            .onChange(of: root.editorLinkModel.folderListController.listDisplayModel.listMode) {
//                root.editorLinkModel.update()
//            }
//            .onChange(of: root.editorLinkModel.folderListController.searchModel.searchText) {
//                root.editorLinkModel.update()
//            }
//            .navigationTitle(root.editorLinkModel.selection.title)
//            .navigationBarTitleDisplayMode(.inline)
//        }
//    }
//        
//    @ViewBuilder func pickerRow(modules: [NetworkModules]) -> some View {
//        @Bindable var editorLinkModel = root.editorLinkModel
//        
//        Picker(selection: $editorLinkModel.selection) {
//            ForEach(modules, id: \.self) { module in
//                buttonPicker(module: module)
//            }
//        } label: {
//            Text("Module selection", bundle: .module)
//        }
//        .labelsHidden()
//        .pickerStyle(.segmented)
//        .padding(.horizontal)
//    }
//    
//    func buttonPicker(module: NetworkModules) -> some View {
//        Image(systemName: module.icon)
//            .tag(module)
//    }
//    
//    var selectionMode: Bool {
//        selectedEntryId != nil
//    }
//}
//
//#Preview(traits: .mockData) {
//    @Previewable @Environment(TableRootModel.self) var root
//    EditorLinkView(root: root, selectedEntryId: UUID())
//}
