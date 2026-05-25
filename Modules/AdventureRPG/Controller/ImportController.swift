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
    let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }

    var editControllable: any EditControllable { editController }

    @MainActor public func makeImportConfiguration() -> ImportConfiguration {
        ImportConfiguration(importModel: importModel)
    }

    public func additionalImport(from inputStream: InputStream, forceSave: Bool, configuration: ImportConfiguration, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws {
        await logImport(title: "additional", count: 0, configuration: configuration)
        try await root.audioRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
        try await root.diceRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
        try await root.mapRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
        try await root.pdfRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
        try await root.photoRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
        try await root.spaceRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
        try await root.tableRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
        try await root.characterRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
        try await root.weatherRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
    }
}
