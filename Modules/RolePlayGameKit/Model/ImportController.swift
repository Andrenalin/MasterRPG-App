// @copyright André Trettin

import CoreRPG
import Foundation
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

struct ImportController: Sendable {
    @MainActor
    init(appModel: AppModel) {
        self.root = appModel
        self.module = .none
        self.itemControllable = appModel.mapRoot.itemControllable
        self.importModel = ItemDataImportModel(gameImporter: false)
    }
    
    weak var root: AppModel!
    let module: NetworkModules
    let itemControllable: ItemControllable
    public let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {

    public func additionalImport(from inputStream: InputStream, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws {
        await logImport(title: "additional", count: 0)
        if await importModel.gameImporter {
            try await root.audioRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.diceRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.mapRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.pdfRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.photoRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.spaceRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.tableRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.characterRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.weatherRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
        } else {
            await setOverwite()
            try await root.audioRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.diceRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.mapRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.pdfRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.photoRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.spaceRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.tableRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.characterRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.weatherRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
        }
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
