// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class EditorLinkModel {
    public init(
        folderListController: any FolderListControllable,
        adventureSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        audioSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        characterSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        diceSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        mapSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        pdfSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
        photoSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        ruleSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
        spaceSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        tableSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        weatherSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
        firstRow: [NetworkModules],
        secondRow: [NetworkModules] = [],
        selection: NetworkModules
    ) {
        self.folderListController = folderListController
        self.adventureSelectionModel = adventureSelectionModel
        self.audioSelectionModel = audioSelectionModel
        self.characterSelectionModel = characterSelectionModel
        self.diceSelectionModel = diceSelectionModel
        self.mapSelectionModel = mapSelectionModel
        self.pdfSelectionModel = pdfSelectionModel
        self.photoSelectionModel = photoSelectionModel
        self.ruleSelectionModel = ruleSelectionModel
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
    
    @ObservationIgnored public var rootManager: RootManager?
    public var folderListController: FolderListControllable
    
    public let adventureSelectionModel: ItemSelectionModel
    public let audioSelectionModel: ItemSelectionModel
    public let characterSelectionModel: ItemSelectionModel
    public let diceSelectionModel: ItemSelectionModel
    public let mapSelectionModel: ItemSelectionModel
    public let pdfSelectionModel: ItemSelectionModel
    public let photoSelectionModel: ItemSelectionModel
    public let ruleSelectionModel: ItemSelectionModel
    public let spaceSelectionModel: ItemSelectionModel
    public let tableSelectionModel: ItemSelectionModel
    public let weatherSelectionModel: ItemSelectionModel

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
        guard let moduleListController else { return }

        folderListController.listDisplayModel.displayMode = moduleListController.listDisplayModel.displayMode
        folderListController.listDisplayModel.listMode = moduleListController.listDisplayModel.listMode
        folderListController.searchModel.searchText = moduleListController.searchModel.searchText
        folderListController.searchModel.selectedTokens = moduleListController.searchModel.selectedTokens
        folderListController.searchModel.searchTags = moduleListController.searchModel.searchTags
    }
    
    func update() {
        guard let moduleListController else { return }

        moduleListController.listDisplayModel.displayMode <=> folderListController.listDisplayModel.displayMode
        moduleListController.listDisplayModel.listMode <=> folderListController.listDisplayModel.listMode
        moduleListController.searchModel.searchText <=> folderListController.searchModel.searchText
        moduleListController.searchModel.selectedTokens <=> folderListController.searchModel.selectedTokens
        moduleListController.searchModel.searchTags <=> folderListController.searchModel.searchTags
    }
    
    private var moduleListController: FolderListControllable? {
        guard let rootManager else { return nil }

        switch selection {
        case .adventure: return rootManager.adventureRoot.folderLinkControllable
        case .audio: return rootManager.audioRoot.folderLinkControllable
        case .dice: return rootManager.diceRoot.folderLinkControllable
        case .map: return rootManager.mapRoot.folderLinkControllable
        case .pdf: return rootManager.pdfRoot.folderLinkControllable
        case .photo: return rootManager.photoRoot.folderLinkControllable
        case .rule: return rootManager.ruleRoot.folderLinkControllable
        case .space: return rootManager.spaceRoot.folderLinkControllable
        case .table: return rootManager.tableRoot.folderLinkControllable
        case .value: return rootManager.characterRoot.folderLinkControllable
        case .weather: return rootManager.weatherRoot.folderLinkControllable
        case .none, .game, .setting, .editor, .search, .generator: return nil
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
        case .rule: ruleSelectionModel
        case .space: spaceSelectionModel
        case .table: tableSelectionModel
        case .value: characterSelectionModel
        case .weather: weatherSelectionModel
        case .none, .game, .setting, .editor, .search, .generator: adventureSelectionModel
        }
    }
    
    func addLinkAndReset(editController: any EntryDataEditable, destiantionItemId: UUID, destinationEntryId: UUID?) {
        guard let destinationEntryId else { return }

        for module in firstRow {
            addLinkAndReset(editController: editController, destiantionItemId: destiantionItemId, destinationEntryId: destinationEntryId, module: module)
        }
        for module in secondRow {
            addLinkAndReset(editController: editController, destiantionItemId: destiantionItemId, destinationEntryId: destinationEntryId, module: module)
        }
    }
    
    private func addLinkAndReset(editController: any EntryDataEditable, destiantionItemId: UUID, destinationEntryId: UUID, module: NetworkModules) {
        guard let rootController = rootManager?.itemRootController(for: module) else { return }

        let selection = selectionModel(for: module)
        for itemSelection in selection.selection {
            let item = rootController.itemControllable.itemOrEmpty(for: itemSelection.itemId)
            let entryId = itemSelection.entryId
            let name = if let entryId { item.urlName(entryId: entryId) } else { item.urlName() }
            editController.add(link: name, module: module, itemId: itemSelection.itemId, entryId: itemSelection.entryId, destinationItemId: destiantionItemId, destinationEntryId: destinationEntryId)
        }
        selection.resetSelection(itemId: nil, entryId: nil)
    }
}
