// @copyright André Trettin

import AndrenalinKit
import AVFoundation
import CoreData
import SwiftUI

@MainActor @Observable
public final class RootModel: Sendable {
    
    @MainActor
    public var selectedItem: ItemRowModel?
    @MainActor
    public var gameItemSelection: ItemRowModel?
    
    @ObservationIgnored
    var listModels: [UUID: ListModel] = [:]
}

@Observable
public final class AudioRoot: @unchecked Sendable {
    
    @MainActor
    init(context: NSManagedObjectContext?) {
        rootModel = RootModel()
        
        if let context {
            dataController = DataController(root: self, context: context, token: NetworkModules.audio.token)
        }
        _fileController = FileController(root: self)
        _itemController = ItemController(root: self, dataController: dataController)
        _editControllers = [EditTypes.main: EditController(root: self, currentListItem: nil, currentModel: nil)]
        _exportController = ExportController(root: self, gameExporter: false)
        _importController = ImportController(root: self, itemController: self.itemController)
        _gameController = GameController(root: self, itemController: self.itemController)
        _linkController = LinkController(root: self, itemController: self.itemController)
        _viewController = ViewController(root: self)
        _audioController = AudioController(root: self)
    }

    public let rootModel: RootModel
    
    @ObservationIgnored
    private(set) var dataController: DataController?

    @ObservationIgnored
    private(set) var _fileController: FileController?
    var fileController: FileController {
        _fileController.unsafelyUnwrapped
    }

    public var fileUrlDataController: FileUrlDataController {
        fileController.fileUrlDataController
    }

    @ObservationIgnored
    private(set) var _itemController: ItemController?
    var itemController: ItemController {
        _itemController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private var _editControllers: [EditTypes: EditController] = [:]
    
    @ObservationIgnored
    private(set) var _exportController: ExportController?
    var exportController: ExportController {
        _exportController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _importController: ImportController?
    var importController: ImportController {
        _importController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _gameController: GameController?
    var gameController: GameController {
        _gameController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _linkController: LinkController?
    public var linkController: LinkController {
        _linkController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _viewController: ViewController?
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _audioController: AudioController?
    var audioController: AudioController {
        _audioController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _rootControllable: RootControllable?
    var rootControllable: RootControllable {
        _rootControllable.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var mainListController: ListController?
}

extension AudioRoot {
    public var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    public var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    public var gameControllable: any (GameControllable & AudioGameStoreable) {
        gameController
    }
    public var itemControllable: any ItemControllable {
        itemController
    }
    
    func applyToAllEditController(handler: @escaping @Sendable (EditController) async -> Void) async {
        for editController in _editControllers.values {
            await handler(editController)
        }
    }

    @MainActor
    func editController(for item: ItemRowTreeModel? = nil, type: EditTypes) -> EditController {
        guard let oldEditController = _editControllers[type] else {
            let model = item.map { itemController.itemOrEmpty(for: $0.model.itemId) }
            let newEditController = EditController(root: self, currentListItem: item, currentModel: model)
            _editControllers[type] = newEditController
            return newEditController
        }
        return oldEditController
    }
    
    @MainActor
    private var listController: ListController {
        ListController(itemController: itemController, listStoreName: "Audio", hasChildren: true, searchToken: .all, categoryTags: itemController.itemDataModel.categoryTags)
    }
    func listController(model: ListModel) -> ListController {
        ListController(itemController: itemController, itemListModel: model)
    }
    @MainActor
    func listController(tabId: UUID, focus: ItemRowModel? = nil) -> ListController {
        guard let listModel = rootModel.listModels[tabId] else {
            let newController = listController
            newController.update(models: itemController.itemDataModel.items.map { ItemRowModel(itemId: $0, typeId: itemController.itemDataModel.networkModule) })
            if let focus {
                newController.setFocusItem(model: focus)
            }
            setMainListController(newController)
            rootModel.listModels[tabId] = newController.model
            return newController
        }
        return listController(model: listModel)
    }
        
    @MainActor
    public func setRootControllable(_ rootControllable: RootControllable) {
        self._rootControllable = rootControllable
        Task {
            dataController?.start()
        }
    }
    
    @MainActor
    private func setMainListController(_ listController: ListController) {
        guard mainListController == nil else { return }
        mainListController = listController
    }
}

// MARK: - AudioPlayer

extension AudioRoot {
    @MainActor
    public var audioCoordinatorPlayback: AudioListenerCoordinator? {
        audioController.model.coordinator
    }
}
