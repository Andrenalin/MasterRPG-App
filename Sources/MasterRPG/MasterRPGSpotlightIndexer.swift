// @copyright André Trettin

#if !os(tvOS)

import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import GeneratorRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RolePlayGameKit
import SpaceRPG
import TableRPG
import WeatherRPG

@MainActor
enum MasterRPGSpotlightIndexer {
    static func reindexAll(appModel: AppModel) async {
        await AdventureShortcutCatalog.reindexAll(root: appModel.adventureRoot)
        await AudioShortcutCatalog.reindexAll(root: appModel.audioRoot)
        await CharacterShortcutCatalog.reindexAll(root: appModel.characterRoot)
        await DiceShortcutCatalog.reindexAll(root: appModel.diceRoot)
        await GeneratorShortcutCatalog.reindexAll(root: appModel.generatorRoot)
        await MapShortcutCatalog.reindexAll(root: appModel.mapRoot)
        await PdfShortcutCatalog.reindexAll(root: appModel.pdfRoot)
        await PhotoShortcutCatalog.reindexAll(root: appModel.photoRoot)
        await SpaceShortcutCatalog.reindexAll(root: appModel.spaceRoot)
        await TableShortcutCatalog.reindexAll(root: appModel.tableRoot)
        await WeatherShortcutCatalog.reindexAll(root: appModel.weatherRoot)
    }
}

#endif
