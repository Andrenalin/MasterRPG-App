// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class EditorLinkModel {
    public init(rootManager: RootManager,
        folderListController: any FolderListControllable,
        adventureSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        audioSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        characterSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        diceSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        mapSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        pdfSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        photoSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        spaceSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        tableSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        weatherSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        firstRow: [NetworkModules],
        secondRow: [NetworkModules] = [],
        selection: NetworkModules
    ) {
        self.rootManager = rootManager
        self.folderListController = folderListController
        self.adventureSelectionModel = adventureSelectionModel
        self.audioSelectionModel = audioSelectionModel
        self.characterSelectionModel = characterSelectionModel
        self.diceSelectionModel = diceSelectionModel
        self.mapSelectionModel = mapSelectionModel
        self.pdfSelectionModel = pdfSelectionModel
        self.photoSelectionModel = photoSelectionModel
        self.spaceSelectionModel = spaceSelectionModel
        self.tableSelectionModel = tableSelectionModel
        self.weatherSelectionModel = weatherSelectionModel
        self.firstRow = firstRow
        self.secondRow = secondRow
        self.selection = selection
        self.selectionFirstRow = nil
        self.selectionSecondRow = nil

        update(selection: selection)
    }
    
    let rootManager: RootManager
    let folderListController: FolderListControllable
    
    let adventureSelectionModel: ItemSelectionModel
    let audioSelectionModel: ItemSelectionModel
    let characterSelectionModel: ItemSelectionModel
    let diceSelectionModel: ItemSelectionModel
    let mapSelectionModel: ItemSelectionModel
    let pdfSelectionModel: ItemSelectionModel
    let photoSelectionModel: ItemSelectionModel
    let spaceSelectionModel: ItemSelectionModel
    let tableSelectionModel: ItemSelectionModel
    let weatherSelectionModel: ItemSelectionModel

    public let firstRow: [NetworkModules]
    let secondRow: [NetworkModules]

    var selection: NetworkModules
    var selectionFirstRow: NetworkModules? = nil
    var selectionSecondRow: NetworkModules? = nil
    
    var preselectedModule: NetworkModules? = nil

    public var modulesRow: [NetworkModules] {
        firstRow + secondRow
    }
        
    func update(selection: NetworkModules) {
        self.selection <=> selection
        if firstRow.contains(selection) {
            selectionFirstRow <=> selection
            selectionSecondRow <=> nil
        }
        if secondRow.contains(selection) {
            selectionFirstRow <=> nil
            selectionSecondRow <=> selection
        }
    }
    
    func updateListController() {
        folderListController.listDisplayModel.displayMode = moduleListController.listDisplayModel.displayMode
        folderListController.listDisplayModel.listMode = moduleListController.listDisplayModel.listMode
        folderListController.searchModel.searchText = moduleListController.searchModel.searchText
        folderListController.searchModel.selectedTokens = moduleListController.searchModel.selectedTokens
        folderListController.searchModel.searchTags = moduleListController.searchModel.searchTags
    }
    
    func update() {
        moduleListController.listDisplayModel.displayMode <=> folderListController.listDisplayModel.displayMode
        moduleListController.listDisplayModel.listMode <=> folderListController.listDisplayModel.listMode
        moduleListController.searchModel.searchText <=> folderListController.searchModel.searchText
        moduleListController.searchModel.selectedTokens <=> folderListController.searchModel.selectedTokens
        moduleListController.searchModel.searchTags <=> folderListController.searchModel.searchTags
    }
    
    private var moduleListController: FolderListControllable {
        switch selection {
        case .adventure: rootManager.adventureRoot.folderLinkControllable
        case .audio: rootManager.audioRoot.folderLinkControllable
        case .dice: rootManager.diceRoot.folderLinkControllable
        case .map: rootManager.mapRoot.folderLinkControllable
        case .pdf: rootManager.pdfRoot.folderLinkControllable
        case .photo: rootManager.photoRoot.folderLinkControllable
        case .space: rootManager.spaceRoot.folderLinkControllable
        case .table: rootManager.tableRoot.folderLinkControllable
        case .value: rootManager.characterRoot.folderLinkControllable
        case .weather: rootManager.weatherRoot.folderLinkControllable
        default: rootManager.adventureRoot.folderLinkControllable
        }
    }
    
    func selectionModel(for module: NetworkModules) -> ItemSelectionModel {
        switch module {
        case .adventure: adventureSelectionModel
        case .audio: audioSelectionModel
        case .dice: diceSelectionModel
        case .map: mapSelectionModel
        case .pdf: pdfSelectionModel
        case .photo: photoSelectionModel
        case .space: spaceSelectionModel
        case .table: tableSelectionModel
        case .value: characterSelectionModel
        case .weather: weatherSelectionModel
        default: adventureSelectionModel
        }
    }
    
    func addLinkAndReset(editController: any EntryDataEditable, destiantionItemId: UUID, destinationEntryId: UUID?) {
        guard let destinationEntryId else { return }

        for module in firstRow {
            addLinkAndReset(editController: editController, destiantionItemId: destinationEntryId, destinationEntryId: destinationEntryId, module: module)
        }
        for module in secondRow {
            addLinkAndReset(editController: editController, destiantionItemId: destinationEntryId, destinationEntryId: destinationEntryId, module: module)
        }
    }

    private func addLinkAndReset(editController: any EntryDataEditable, destiantionItemId: UUID, destinationEntryId: UUID, module: NetworkModules) {
        guard let rootController = rootManager.itemRootController(for: module) else { return }

        let model = selectionModel(for: module)
        for item in model.selection {
            let name = rootController.itemControllable.itemOrEmpty(for: item.itemId).name.withoutLink()
            editController.add(link: name, module: module, itemId: item.itemId, entryId: item.entryId, destinationItemId: destiantionItemId, destinationEntryId: destinationEntryId)
        }
        model.resetSelection(itemId: nil)
    }
}
