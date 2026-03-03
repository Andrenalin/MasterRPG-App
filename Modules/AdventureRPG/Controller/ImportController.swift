// @copyright André Trettin

import CoreRPG
import Foundation
import AudioRPG
import WeatherRPG
import TableRPG
import CharacterRPG
import PhotoRPG
import PdfRPG
import DiceRPG
import MapRPG
import SpaceRPG

struct ImportController: Sendable {
    @MainActor
    init(root: AdventureRootModel, itemController: ItemController) {
        self.root = root
        self.itemController = itemController
        self.editController = root.editController
        self.importModel = ItemDataImportModel()
    }
    
    let root: AdventureRootModel
    let itemController: ItemController
    let editController: EditController
    public let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    
    var editControllable: any EditControllable { editController }
    
    public func additionalImport(from inputStream: InputStream, forceSave: Bool, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws {
        await logImport(title: "additional", count: 0)
        await setOverwite()
        try await root.audioRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)
        try await root.diceRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)
        try await root.mapRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)
        try await root.pdfRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)
        try await root.photoRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)
        try await root.spaceRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)
        try await root.tableRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)
        try await root.characterRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)
        try await root.weatherRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)
    }
    
    @MainActor
    private func setOverwite() async {
        root.audioRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
        root.diceRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
        root.mapRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
        root.pdfRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
        root.photoRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
        root.spaceRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
        root.tableRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
        root.characterRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
        root.weatherRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
    }
}
