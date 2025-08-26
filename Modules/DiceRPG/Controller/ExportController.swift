// @copyright André Trettin

import CoreRPG
import Foundation

struct ExportController: Sendable {
    @MainActor
    init(module: NetworkModules, itemController: any ItemControllable, gameExporter: Bool) {
        self.module = module
        self.itemControllable = itemController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }
    
    public let exportModel: ItemDataExportModel
    var fileUrlDataController: FileUrlDataController?
    var itemControllable: any ItemControllable
    
    var module: NetworkModules
    var version: Int { 2024 }
}

extension ExportController: ExportControllable {}
