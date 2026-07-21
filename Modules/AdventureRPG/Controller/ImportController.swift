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
import RuleRPG
import SpaceRPG

struct ImportController: Sendable {
    @MainActor
    init(root: AdventureRootModel, itemController: ItemController) {
        self.root = root
        self.itemController = itemController
        self.editController = root.editController
    }

    let root: AdventureRootModel
    let itemController: ItemController
    let editController: EditController
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }

    var editControllable: any EditControllable { editController }

    public func additionalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel) async throws {
        await logImport(title: "additional", count: 0, importModel: importModel)
        try await root.audioRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
        try await root.diceRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
        try await root.mapRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
        try await root.pdfRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
        try await root.photoRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
        try await root.spaceRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
        try await root.tableRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
        try await root.characterRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
        try await root.weatherRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
    }

    public func finalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel) async throws {
        try await root.ruleRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
    }
}
