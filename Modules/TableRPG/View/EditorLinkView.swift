// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI


@MainActor @Observable
final class EditorLinkModel {
    init(rootManager: RootManager, folderListController: FolderListControllable) {
        self.rootManager = rootManager
        self.folderListController = folderListController
    }
    var rootManager: RootManager
    
    var folderListController: FolderListControllable
    
    var selection: NetworkModules = .table
    var diceSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false)
    var tableSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    
    var firstRow: [NetworkModules] {
        [.table, .dice]
    }
    
    func updateListController() {
        let moduleListController = switch selection {
        case .dice:
            rootManager.diceRoot.folderLinkControllable
        default:
            rootManager.tableRoot.folderLinkControllable
        }
        
        folderListController.listDisplayModel.displayMode = moduleListController.listDisplayModel.displayMode
        folderListController.listDisplayModel.listMode = moduleListController.listDisplayModel.listMode
        folderListController.searchModel.searchText = moduleListController.searchModel.searchText
        folderListController.searchModel.selectedTokens = moduleListController.searchModel.selectedTokens
        folderListController.searchModel.searchTags = moduleListController.searchModel.searchTags
    }
    
    func update() {
        let moduleListController = switch selection {
        case .dice:
            rootManager.diceRoot.folderLinkControllable
        default:
            rootManager.tableRoot.folderLinkControllable
        }
        
        moduleListController.listDisplayModel.displayMode <=>
        folderListController.listDisplayModel.displayMode
        moduleListController.listDisplayModel.listMode <=> folderListController.listDisplayModel.listMode
        moduleListController.searchModel.searchText <=> folderListController.searchModel.searchText
        moduleListController.searchModel.selectedTokens <=> folderListController.searchModel.selectedTokens
        moduleListController.searchModel.searchTags <=> folderListController.searchModel.searchTags
    }
    
    func addLinkAndReset(editController: any EntryDataEditable, destinationEntryId: UUID?) {
        guard let destinationEntryId else { return }

        for module in firstRow {
            addLinkAndReset(editController: editController, destinationEntryId: destinationEntryId, module: module)
        }
    }

    private func addLinkAndReset(editController: any EntryDataEditable, destinationEntryId: UUID, module: NetworkModules) {
        let selectionModel = switch module {
        case .dice: diceSelectionModel
        default: tableSelectionModel
        }
        
        let rootController = switch module {
        case .dice: rootManager.diceRoot
        default: rootManager.tableRoot
        }

        for item in selectionModel.selection {
            let name = rootController.itemControllable.itemOrEmpty(for: item.itemId).name.withoutLink()
            editController.add(link: name, module: module, itemId: item.itemId, entryId: item.entryId, destinationEntryId: destinationEntryId)
        }
        selectionModel.resetSelection(itemId: nil)
    }
}

struct EditorLinkView: View {
    init(root: TableRootModel, selectedModule: NetworkModules = .table, selectedEntryId: UUID? = nil) {
        self.root = root
        self.selectedEntryId = selectedEntryId
        root.editorLinkModel.selection = selectedModule
    }
    
    let root: TableRootModel
    let selectedEntryId: UUID?
        
    var body: some View {
        ManagedNavigationStack(name: "TableEditorLink") {
            VStack {
                pickerRow(modules: root.editorLinkModel.firstRow)
                
                ZStack {
                    root.diceRoot.viewController.linkListView(type: selectionMode ? .selectionInline : .inspector, itemSelectionModel: root.editorLinkModel.diceSelectionModel)
                        .opacity(root.editorLinkModel.selection == .dice ? 1 : 0)
                    root.viewController.linkListView(type: selectionMode ? .selectionInline : .inspector, itemSelectionModel: root.editorLinkModel.tableSelectionModel)
                        .opacity(root.editorLinkModel.selection == .table ? 1 : 0)
                }
            }
            .toolbarItemListModifier(root: root, listControllable: root.editorLinkModel.folderListController, parentModel: nil, modal: true) {
                root.editorLinkModel.addLinkAndReset(editController: root.editController, destinationEntryId: selectedEntryId)
            }
            .searchItemList(listControllable: root.editorLinkModel.folderListController)
            .environment(root.editorLinkModel.folderListController.cacheListItemModel)
            .onChange(of: root.editorLinkModel.selection, initial: true) {
                root.editorLinkModel.updateListController()
            }
            .onChange(of: root.editorLinkModel.folderListController.listDisplayModel.displayMode) {
                root.editorLinkModel.update()
            }
            .onChange(of: root.editorLinkModel.folderListController.listDisplayModel.listMode) {
                root.editorLinkModel.update()
            }
            .onChange(of: root.editorLinkModel.folderListController.searchModel.searchText) {
                root.editorLinkModel.update()
            }
            .navigationTitle(root.editorLinkModel.selection.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
        
    @ViewBuilder func pickerRow(modules: [NetworkModules]) -> some View {
        @Bindable var editorLinkModel = root.editorLinkModel
        
        Picker(selection: $editorLinkModel.selection) {
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
    
    var selectionMode: Bool {
        selectedEntryId != nil
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(TableRootModel.self) var root
    EditorLinkView(root: root, selectedEntryId: UUID())
}
