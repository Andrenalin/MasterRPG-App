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
        AdventureIntentSupport.registerDonations()
        AudioIntentSupport.registerDonations()
        CharacterIntentSupport.registerDonations()
        DiceIntentSupport.registerDonations()
        GeneratorIntentSupport.registerDonations()
        MapIntentSupport.registerDonations()
        PdfIntentSupport.registerDonations()
        PhotoIntentSupport.registerDonations()
        RuleIntentSupport.registerDonations()
        SpaceIntentSupport.registerDonations()
        TableIntentSupport.registerDonations()
        WeatherIntentSupport.registerDonations()
    }

    /// The adventure names the shortcut parameters were last refreshed with.
    private static var lastShortcutNames: [String]?

    /// Indexes what changed since the last pass; a module without changes costs nothing. The
    /// parameterized phrases ("Open <adventure>", "Start <adventure>") only depend on the
    /// adventure names, so the system's parameter cache is refreshed when the names differ from the
    /// last refresh (and once per launch), not after every edit. See CODE_AUDIT_AppIntents §7.1, §7.2
    /// and CODE_AUDIT §5.4.
    static func reindexChanged(appModel: AppModel) async {
        await AdventureIntentSupport.reindexChanged(root: appModel.adventureRoot)
        let names = AdventureIntentSupport.shortcutNames(root: appModel.adventureRoot)
        if names != lastShortcutNames {
            lastShortcutNames = names
            MasterRPGShortcuts.updateAppShortcutParameters()
        }
        await AudioIntentSupport.reindexChanged(root: appModel.audioRoot)
        await CharacterIntentSupport.reindexChanged(root: appModel.characterRoot)
        await DiceIntentSupport.reindexChanged(root: appModel.diceRoot)
        await GeneratorIntentSupport.reindexChanged(root: appModel.generatorRoot)
        await MapIntentSupport.reindexChanged(root: appModel.mapRoot)
        await PdfIntentSupport.reindexChanged(root: appModel.pdfRoot)
        await PhotoIntentSupport.reindexChanged(root: appModel.photoRoot)
        await RuleIntentSupport.reindexChanged(root: appModel.ruleRoot)
        await SpaceIntentSupport.reindexChanged(root: appModel.spaceRoot)
        await TableIntentSupport.reindexChanged(root: appModel.tableRoot)
        await WeatherIntentSupport.reindexChanged(root: appModel.weatherRoot)
    }
}

#endif
