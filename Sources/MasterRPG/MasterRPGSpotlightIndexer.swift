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
    /// deletes them, and how its items are exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    static func registerDonations(appModel: AppModel) {
        AdventureIntentSupport.registerDonations(root: appModel.adventureRoot)
        AudioIntentSupport.registerDonations(root: appModel.audioRoot)
        CharacterIntentSupport.registerDonations(root: appModel.characterRoot)
        DiceIntentSupport.registerDonations(root: appModel.diceRoot)
        GeneratorIntentSupport.registerDonations(root: appModel.generatorRoot)
        MapIntentSupport.registerDonations(root: appModel.mapRoot)
        PdfIntentSupport.registerDonations(root: appModel.pdfRoot)
        PhotoIntentSupport.registerDonations(root: appModel.photoRoot)
        RuleIntentSupport.registerDonations(root: appModel.ruleRoot)
        SpaceIntentSupport.registerDonations(root: appModel.spaceRoot)
        TableIntentSupport.registerDonations(root: appModel.tableRoot)
        WeatherIntentSupport.registerDonations(root: appModel.weatherRoot)
    }

    /// Indexes what changed since the last pass; a module without changes costs nothing. No App
    /// Shortcut phrase takes a parameter any more, so there is no parameter cache to refresh.
    /// See CODE_AUDIT_AppIntents §7.1, CODE_AUDIT_Since_3.0.1 §4.3.
    static func reindexChanged(appModel: AppModel) async {
        await AdventureIntentSupport.reindexChanged(root: appModel.adventureRoot)
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
