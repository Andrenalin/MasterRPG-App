// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RPGResources
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG

public extension AdventureRootModel {
    @MainActor
    static let preview: AdventureRootModel = previewFixture()

    @MainActor
    static func previewFixture() -> AdventureRootModel {
        previewFixture(models: AdventureModel.previewFixtures)
    }

    @MainActor
    internal static func previewFixture(models: [AdventureModel]) -> AdventureRootModel {
        let ruleRoot = RuleFactory.root(tagController: .preview)
        let root = AdventureRootModel(tagController: .preview, audioRoot: .preview, diceRoot: .preview, generatorRoot: nil, mapRoot: .preview, pdfRoot: .preview, photoRoot: .preview, ruleRoot: ruleRoot, spaceRoot: .preview, tableRoot: .preview, characterRoot: .preview, weatherRoot: .preview)
        let rootManager = RootManager(adventureRoot: root, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root.mapRoot, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, ruleRoot: ruleRoot, spaceRoot: root.spaceRoot, tableRoot: root.tableRoot, weatherRoot: root.weatherRoot)
        root.setUp(root: rootManager, context: nil)
        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }
        root.editController.setCurrentItem(to: .preview)
        return root
    }
    
    @MainActor
    static let previewWithData: AdventureRootModel = {
        let root = AdventureRootModel.preview
        let importController = root.importController
        let editController = root.editController
#if DEBUG
        let url = RPGResources.Resources.bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz")
        Task(priority: .userInitiated) {
            guard await PreviewFixtureLoader.importFirstExample(url: url, into: importController) else { return }
            Task { @MainActor in
                editController.setCurrentItem(to: .previewWithData)
            }
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot(audioRoot: AudioRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel) -> AdventureRootModel {
        let ruleRoot = RuleFactory.root(tagController: .preview)
        let root = AdventureRootModel(tagController: .preview, audioRoot: audioRoot, diceRoot: diceRoot, generatorRoot: nil, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, ruleRoot: ruleRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot)
        let rootManager = RootManager(adventureRoot: root, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root.mapRoot, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, ruleRoot: ruleRoot, spaceRoot: root.spaceRoot, tableRoot: root.tableRoot, weatherRoot: root.weatherRoot)
        root.setUp(root: rootManager, context: nil)
        root.editController.setCurrentItem(to: .preview)
        return root
    }
#endif
}

// MARK: Preview - Test
extension AdventureModel {
    nonisolated static let previewId = UUID(uuid: (0x5F, 0x6D, 0x6D, 0x52, 0x3D, 0xDB, 0x4B, 0x20, 0x8D, 0x45, 0xDF, 0xB5, 0x43, 0x79, 0x94, 0x17))
    @MainActor
    static var preview: AdventureModel {
        AdventureModel(
            id: previewId,
            name: "Das Geheimnis der Goblinburg",
            description: "A goblin-held fortress needs a band of heroes.",
            tags: ["DS", "1-4", "Dungeon"],
            photoId: PhotoRootModel.previewPhotoId,
            entries: [
                AdventureEntryModel(
                    id: entryUuid,
                    name: "Ground Floor",
                    content: "The first room behind the ruined gate. Study the [Goblinburg Map](RPG://MAPS/0/50DFDB6F-E8B1-41A4-A409-911D888119E8) before entering."
                ),
                AdventureEntryModel(
                    id: entryUuid2,
                    name: "The Boss Chamber",
                    content: "[Thrak the Cruel](RPG://VALUES/0/1527140F-0101-46C3-912E-B02FE0FF7696) commands from the throne. Roll [Quick Strike](RPG://DICE/0/2201FBB7-0403-4A18-A361-CAD5A76A637D) to initiate combat."
                ),
                AdventureEntryModel(
                    id: entryUuid3,
                    name: "Loot & Rewards",
                    content: "Roll on [Goblin Loot](RPG://TABLES/0/25321D0A-CBAC-4A6C-944C-C8916049FC45) for treasure after the fight."
                ),
                AdventureEntryModel(
                    id: entryUuid4,
                    name: "Atmosphere",
                    content: "Dim torchlight and growls fill the halls. Play [Storm over Emberkeep](RPG://AUDIOS/0/00000000-0000-0000-0000-000000000021) to set the mood."
                ),
                AdventureEntryModel(
                    id: entryUuid5,
                    name: "Sequel Hook",
                    content: "Survivors claim the overlord fled to [Asche der Drachen](RPG://ADVENTURES/0/\(uuid2.uuidString)) for refuge."
                )
            ]
        )
    }
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: AdventureModel.previewId, typeId: .adventure)
    @MainActor
    static var previewWithData: ItemRowTreeModel = {
        let root = AdventureRootModel.previewWithData
        return ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], entryId: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]).entries[0].id, typeId: .map)
    }()
}

extension ItemController {
    @MainActor
    static let preview = AdventureRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = AdventureRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static let preview = AdventureRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static let preview = AdventureRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static let preview = AdventureRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static let preview = AdventureRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static let preview = AdventureRootModel.preview.linkController
}

extension AdventureModel {
    static let entryUuid  = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x11))
    static let entryUuid2 = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x14))
    static let entryUuid3 = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x15))
    static let entryUuid4 = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x16))
    static let entryUuid5 = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x17))

    static let uuid2 = UUID(uuid: (0x8C, 0x94, 0x28, 0x8B, 0x4C, 0xDB, 0x41, 0x09, 0xB0, 0xAD, 0x75, 0xB1, 0x25, 0x30, 0xED, 0x84))
    static let uuid3 = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x13))

    static var previewFixtures: [AdventureModel] {
        [
            preview,
            AdventureModel(
                id: uuid2,
                name: "Asche der Drachen",
                description: "A longer adventure fixture for wrapping and list layouts.",
                tags: ["DS", "5-8", "Original"],
                photoId: PhotoRootModel.previewPaladinPhotoId,
                entries: [
                    AdventureEntryModel(
                        id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x12)),
                        name: "The Crypt",
                        content: "An ancient mechanism guards the dragon ash."
                    )
                ]
            ),
            AdventureModel(
                id: uuid3,
                name: "Wizard's Tower",
                description: "A compact fixture with a linked character portrait.",
                tags: ["Magic", "Tower"],
                photoId: PhotoRootModel.previewWizardPhotoId
            )
        ]
    }
}
