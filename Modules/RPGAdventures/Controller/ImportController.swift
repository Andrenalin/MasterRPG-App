// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGAudios
import RPGWeathers
import RPGTables
import RPGValues
import PhotoRPG
import RPGPdfs
import RPGDie
import RPGMaps
import SpaceRPG

struct ImportController: Sendable {
    @MainActor
    init(root: AdventureRootModel, itemController: ItemController, gameImporter: Bool) {
        self.root = root
        self.itemController = itemController
        self.importModel = ItemDataImportModel(gameImporter: gameImporter)
    }
    
    weak var root: AdventureRootModel!
    let itemController: ItemController
    public let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }

    public func additionalImport(from inputStream: InputStream, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws {
        await logImport(title: "additional", count: 0)
        if await importModel.gameImporter {
            try await root.audioRoot.gameControllable.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.diceRoot.gameControllable.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.mapRoot.gameControllable.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.pdfRoot.gameControllable.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.photoRoot.gameControllable.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.spaceRoot.gameControllable.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.tableRoot.gameControllable.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.valueRoot.gameControllable.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.weatherRoot.gameControllable.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
        } else {
            await setOverwite()
            try await root.audioRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.diceRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.mapRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.pdfRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.photoRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.spaceRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.tableRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
            try await root.valueRoot.importControllable.importStream(from: inputStream, counterUpdater: counterUpdater)
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
        root.valueRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
        root.weatherRoot.importControllable.importModel.withOverwrite = importModel.withOverwrite
    }
}
