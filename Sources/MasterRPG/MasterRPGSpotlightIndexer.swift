// @copyright André Trettin

#if !os(tvOS)

import AdventureRPG
import AppIntents
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

    /// Whether the shortcut parameters were refreshed once since launch.
    private static var didRefreshShortcutParameters = false

    /// Indexes what changed since the last pass; a module without changes costs nothing. The
    /// parameterized phrases ("Open <adventure>", "Start <adventure>") only depend on the
    /// adventures, so the system's parameter cache is refreshed when those changed, and once per
    /// launch. See CODE_AUDIT_AppIntents §7.1, §7.2.
    static func reindexChanged(appModel: AppModel) async {
        let adventuresChanged = AdventureShortcutCatalog.hasChanges(root: appModel.adventureRoot)
        await AdventureShortcutCatalog.reindexChanged(root: appModel.adventureRoot)
        if adventuresChanged || !didRefreshShortcutParameters {
            didRefreshShortcutParameters = true
            MasterRPGShortcuts.updateAppShortcutParameters()
        }
        await AudioShortcutCatalog.reindexChanged(root: appModel.audioRoot)
        await CharacterShortcutCatalog.reindexChanged(root: appModel.characterRoot)
        await DiceShortcutCatalog.reindexChanged(root: appModel.diceRoot)
        await GeneratorShortcutCatalog.reindexChanged(root: appModel.generatorRoot)
        await MapShortcutCatalog.reindexChanged(root: appModel.mapRoot)
        await PdfShortcutCatalog.reindexChanged(root: appModel.pdfRoot)
        await PhotoShortcutCatalog.reindexChanged(root: appModel.photoRoot)
        await RuleShortcutCatalog.reindexChanged(root: appModel.ruleRoot)
        await SpaceShortcutCatalog.reindexChanged(root: appModel.spaceRoot)
        await TableShortcutCatalog.reindexChanged(root: appModel.tableRoot)
        await WeatherShortcutCatalog.reindexChanged(root: appModel.weatherRoot)
    }
}

#endif
