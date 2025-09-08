// @copyright André Trettin

import CoreRPG
import Foundation

struct ExportController: Sendable {
    @MainActor
    init(module: NetworkModules, itemController: any ItemControllable, fileUrlDataController: FileUrlDataController?, gameExporter: Bool) {
        self.module = module
        self.itemControllable = itemController
        self.fileUrlDataController = fileUrlDataController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }
    
    public let exportModel: ItemDataExportModel
    var fileUrlDataController: FileUrlDataController?
    var itemControllable: any ItemControllable
    
    var module: NetworkModules
    var version: Int { ItemDataExportModel.Version.version_2025.rawValue }
}

extension ExportController: ExportControllable {}
