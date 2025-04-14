// @copyright André Trettin

import AndrenalinKit
import Foundation

struct ImportController: Sendable {
    @MainActor
    init(root: WeatherRoot, itemController: ItemController, gameImporter: Bool) {
        self.root = root
        self.itemController = itemController
        self.importModel = ItemDataImportModel(gameImporter: gameImporter)
    }
    
    weak var root: WeatherRoot!
    let itemController: ItemController
    public let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
}
