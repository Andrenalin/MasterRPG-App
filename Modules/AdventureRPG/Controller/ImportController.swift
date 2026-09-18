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

    public func additionalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws {
        await logImport(title: "additional", count: 0, importModel: importModel)
        // See CODE_AUDIT §9.5 — loops over the shared sibling list (Rule is imported last,
        // via `finalImport`) instead of hand-listing each of the 9 modules.
        for sibling in root.siblingModuleRootsExcludingRule {
            try await sibling.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel, gameMemoryOnly: gameMemoryOnly)
        }
    }

    public func finalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws {
        try await root.ruleRoot.importControllable.importStream(from: inputStream, forceSave: forceSave, importModel: importModel, gameMemoryOnly: gameMemoryOnly)
    }
}
