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
import RuleRPG
import SpaceRPG
import TableRPG
import WeatherRPG

@MainActor
enum MasterRPGSpotlightIndexer {
    /// Tells every module which entity type its donations name, so trashing or purging an item
    /// deletes them. See CODE_AUDIT_AppIntents §4.4.
    static func registerDonations() {
        AdventureShortcutCatalog.registerDonations()
        AudioShortcutCatalog.registerDonations()
        CharacterShortcutCatalog.registerDonations()
        DiceShortcutCatalog.registerDonations()
        GeneratorShortcutCatalog.registerDonations()
        MapShortcutCatalog.registerDonations()
        PdfShortcutCatalog.registerDonations()
        PhotoShortcutCatalog.registerDonations()
        RuleShortcutCatalog.registerDonations()
        SpaceShortcutCatalog.registerDonations()
        TableShortcutCatalog.registerDonations()
        WeatherShortcutCatalog.registerDonations()
    }

    static func reindexAll(appModel: AppModel) async {
        await AdventureShortcutCatalog.reindexAll(root: appModel.adventureRoot)
        await AudioShortcutCatalog.reindexAll(root: appModel.audioRoot)
        await CharacterShortcutCatalog.reindexAll(root: appModel.characterRoot)
        await DiceShortcutCatalog.reindexAll(root: appModel.diceRoot)
        await GeneratorShortcutCatalog.reindexAll(root: appModel.generatorRoot)
        await MapShortcutCatalog.reindexAll(root: appModel.mapRoot)
        await PdfShortcutCatalog.reindexAll(root: appModel.pdfRoot)
        await PhotoShortcutCatalog.reindexAll(root: appModel.photoRoot)
        await RuleShortcutCatalog.reindexAll(root: appModel.ruleRoot)
        await SpaceShortcutCatalog.reindexAll(root: appModel.spaceRoot)
        await TableShortcutCatalog.reindexAll(root: appModel.tableRoot)
        await WeatherShortcutCatalog.reindexAll(root: appModel.weatherRoot)
    }
}

#endif
