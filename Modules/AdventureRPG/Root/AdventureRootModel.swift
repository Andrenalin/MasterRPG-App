// @copyright André Trettin

import Foundation
import SwiftData

import CoreRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

@MainActor @Observable
public final class AdventureRootModel {
    init(modelContext: ModelContext, audioRoot: AudioRootModel, characterRoot: CharacterRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, weatherRoot: WeatherRootModel) {
        self.modelContext = modelContext
        let module: NetworkModules = .adventure
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: module, categoryTags: [.adventure, .campaign, .scenario, .rules, .supplement])
        self.searchModel = searchModel
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        self.audioRoot = audioRoot
        self.characterRoot = characterRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.weatherRoot = weatherRoot
        
        itemController.cleanDeleted()
    }
    
    let modelContext: ModelContext
    public let module: NetworkModules

    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    public var currentSelectedItemId: UUID? {
        listController.listModel.selectedItemId
    }
    public let removeEntryListModel = RemoveEntryListModel()
    
    @ObservationIgnored let audioRoot: AudioRootModel
    @ObservationIgnored let characterRoot: CharacterRootModel
    @ObservationIgnored let diceRoot: DiceRootModel
    @ObservationIgnored let mapRoot: MapRootModel
    @ObservationIgnored let pdfRoot: PdfRootModel
    @ObservationIgnored let photoRoot: PhotoRootModel
    @ObservationIgnored let spaceRoot: SpaceRootModel
    @ObservationIgnored let tableRoot: TableRootModel
    @ObservationIgnored let weatherRoot: WeatherRootModel
    
    @ObservationIgnored lazy var editController: EditController = {
        EditController(itemController: itemController)
    }()
    @ObservationIgnored lazy var exportController: ExportController = {
        ExportController(module: module, itemController: itemController, gameExporter: false)
    }()
    @ObservationIgnored lazy var importController: ImportController = {
        ImportController(itemController: itemController, module: module)
    }()
    @ObservationIgnored public lazy var gameController: AdventureStoreGameable = {
        GameController(root: rootManager, itemController: itemController)
    }()
    @ObservationIgnored lazy var itemController: ItemController = {
        ItemController(container: modelContext.container, module: module)
    }()
    @ObservationIgnored lazy var linkController: LinkController = {
        LinkController(module: module, itemController: itemController)
    }()
    @ObservationIgnored lazy var listController: ListController = {
        ListController.listController(for: .main, listDisplayModel: listDisplayModel, searchModel: searchModel)
    }()
    @ObservationIgnored lazy var listLinkController: ListController = {
        ListController.listController(for: .link, listDisplayModel: listDisplayModel, searchModel: searchModel)
    }()
    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()
    @ObservationIgnored lazy public var rootController: ItemRootController = {
        ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportControllable,
            gameControllable: gameController,
            itemControllable: itemController,
            linkControllable: linkController,
            listControllable: listController,
            listLinkControllable: listLinkController,
            viewControllable: viewController
        )
    }()
}

public extension AdventureRootModel {
    var rootManager: RootManager {
        RootManager(
            adventureRoot: self,
            audioRoot: audioRoot,
            characterRoot: characterRoot,
            diceRoot: diceRoot,
            generatorRoot: self,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            weatherRoot: weatherRoot
        )
    }
}

extension AdventureRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var exportControllable: any ExportControllable { exportController }
    public var gameControllable: any GameControllable { gameController }
    public var importControllable: any ImportControllable { importController }
    public var itemControllable: any ItemControllable { itemController }
    public var linkControllable: any LinkControllable { linkController }
    public var listControllable: any ListControllable { listController }
    public var listLinkControllable: any ListControllable { listLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

public extension AdventureRootModel {
    @MainActor func titleImage(for id: UUID?) async -> AKImage? {
        guard let id else { return nil }
//        let (image, _) = await photoRoot.fetchPhotoImage(for: itemController.itemOrEmpty(for: id).photoId, useGame: false) ?? (nil, 0.0)
//        return image
        return nil
    }
}
