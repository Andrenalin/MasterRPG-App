// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
import PdfRPG
import PhotoRPG
import WeatherRPG
import RPGResources
import TableRPG
import CharacterRPG
import SwiftUI

public extension MapRootModel {
    static let previewValueId = MapModel.previewId

    @MainActor
    static let preview: MapRootModel = previewFixture()

    @MainActor
    internal static func previewFixture(
        models: [MapModel] = MapModel.previewFixtures
    ) -> MapRootModel {
        let root = MapRootModel(tagController: .preview, audioRoot: .preview, diceRoot: .preview, pdfRoot: .preview, photoRoot: .preview, tableRoot: .preview, characterRoot: .preview, weatherRoot: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root.tableRoot, weatherRoot: root)
        root.setUp(context: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }
        root.editController.setCurrentItem(to: .preview)
        if let focusedModel = models.first(where: { $0.id == MapModel.previewId }) {
            root.gameController.setGame(item: focusedModel.copy(), itemId: focusedModel.id)
        }
        return root
    }
    
    @MainActor
    static let previewWithData: MapRootModel = {
        let root = MapRootModel.preview
        let itemController = root.itemController
        let importController = root.importController
        let editController = root.editController
#if DEBUG
        let url = RPGResources.Resources.bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz")
        Task(priority: .userInitiated) {
            guard await PreviewFixtureLoader.importFirstExample(url: url, into: importController) else { return }
            Task { @MainActor in
                editController.setCurrentItem(to: ItemRowTreeModel.previewWithData(with: itemController))
            }
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot(audioRoot: AudioRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel? = nil) -> MapRootModel {
        let root = MapRootModel(tagController: .preview, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot ?? WeatherRootModel.testRoot(photoRoot: photoRoot))
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root.tableRoot, weatherRoot: root)
        root.setUp(context: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.diceRoot.setUp(context: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.photoRoot.setUp(context: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.pdfRoot.setUp(context: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.audioRoot.setUp(context: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.tableRoot.setUp(context: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.characterRoot.setUp(context: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        return root
    }
#endif
}

@MainActor
extension MapRootModel: RootExportControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
}

// MARK: Preview - Test
extension MapModel {
    nonisolated static let previewId = UUID.fixture("50DFDB6F-E8B1-41A4-A409-911D888119E8")
    nonisolated static let previewEmptyId = UUID(uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    @MainActor
    static var preview: MapModel {
        MapModel(
        id: previewId,
        name: "Mega Dungeon",
        description: "Heavy Dungeon",
        tags: ["Master", "Monster", "Hardcore"],
        category: .dungeon,
        displayState: 0,
        entries: [
            MapEntryModel.previewEntrance,
            MapEntryModel.previewGreatHall,
            MapEntryModel.previewTreasureRoom,
            MapEntryModel.previewCorridor,
        ],
        photoId: PhotoRootModel.previewPhotoId,
        width: 1000,
        height: 800,
        mapPins: MapPinModel.previewPins,
        pinScale: 1.0,
        scale: 1.0,
        degrees: 0.0
        )
    }

    /// A deterministic no-content map for controls, empty states, and snapshots.
    @MainActor
    static var previewEmpty: MapModel {
        MapModel(
        id: previewEmptyId,
        name: "Empty Map",
        description: "A blank map fixture.",
        tags: ["Preview"],
        category: .dungeon,
        displayConfig: DisplayConfigModel(
            id: UUID(uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
            tileCoordinates: [],
            border: DisplayBorderViewModel(
                id: UUID(uuid: (0xB1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
            )
        ),
        width: 1_200,
        height: 800
        )
    }

    nonisolated static let previewForestId = UUID.fixture("A2B3C4D5-E6F7-8901-A234-5678901ABCDE")

    @MainActor
    static var previewForest: MapModel {
        MapModel(
            id: previewForestId,
            name: "Shadowfen Crossing",
            description: "A weathered stone bridge over a haunted marsh.",
            tags: ["Outdoor", "Ambient", "Boss"],
            category: .building,
            displayState: 0,
            entries: [
                MapEntryModel.previewFenPath,
                MapEntryModel.previewAncientRuins,
            ],
            width: 900,
            height: 600,
            pinScale: 1.0,
            scale: 1.0,
            degrees: 0.0
        )
    }

    @MainActor
    static var previewFixtures: [MapModel] {
        [preview, previewForest, previewEmpty]
    }
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: MapModel.previewId, entryId: MapEntryModel.previewId, typeId: .map)
    @MainActor
    static func previewWithData(with itemController: ItemController) -> ItemRowTreeModel {
        let item = itemController.itemOrEmpty(for: itemController.itemDataModel.items[0])
        return ItemRowTreeModel(itemId: item.id, entryId: item.entries[0].id, typeId: .map)
    }
}

extension ItemController {
    @MainActor
    static let preview = MapRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = MapRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static let preview = MapRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static let preview = MapRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static let preview = MapRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static let preview = MapRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static let preview = MapRootModel.preview.linkController
}


// MARK: Test Data ViewModels

extension MapModel {
    static let uuid = UUID.fixture("14C7502D-2EDF-4457-AE0D-6152DFA8E8DF")
}

extension MapEntryModel {
    static let previewId: UUID = UUID.fixture("A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

    // Kept for backward compatibility — aliases the entrance room
    @MainActor
    static var preview: MapEntryModel { previewEntrance }

    // Entrance room — bottom-left area
    @MainActor
    static let previewEntrance = MapEntryModel(
        id: UUID.fixture("A1B2C3D4-E5F6-7890-ABCD-EF1234567890"),
        name: "Entrance",
        content: "The dungeon entrance. Torches flicker on damp stone walls. [Andrenalin](RPG://VALUES/0/1527140F-0101-46C3-912E-B02FE0FF7696) guards this hall. Play [Storm over Emberkeep](RPG://AUDIOS/0/00000000-0000-0000-0000-000000000021) for atmosphere.",
        coordinates: [
            CGPoint(x: 50, y: 550),
            CGPoint(x: 250, y: 550),
            CGPoint(x: 250, y: 700),
            CGPoint(x: 50, y: 700),
        ],
        isShown: true
    )

    // Great Hall — center of the map
    @MainActor
    static let previewGreatHall = MapEntryModel(
        id: UUID.fixture("B2C3D4E5-F6A7-8901-BCDE-F12345678901"),
        name: "Great Hall",
        content: "A vast pillared hall. Ancient banners hang from the ceiling. Roll on [Goblin Loot](RPG://TABLES/0/25321D0A-CBAC-4A6C-944C-C8916049FC45) for random encounters. See [Das Geheimnis der Goblinburg](RPG://ADVENTURES/0/5F6D6D52-3DDB-4B20-8D45-DFB543799417) for the plot hook.",
        coordinates: [
            CGPoint(x: 300, y: 200),
            CGPoint(x: 700, y: 200),
            CGPoint(x: 700, y: 550),
            CGPoint(x: 300, y: 550),
        ],
        isShown: false
    )

    // Treasure Room — top-right corner
    @MainActor
    static let previewTreasureRoom = MapEntryModel(
        id: UUID.fixture("C3D4E5F6-A7B8-9012-CDEF-123456789012"),
        name: "Treasure Room",
        content: "Glittering gold fills every corner. Beware the trap floor. Roll [Quick Strike](RPG://DICE/0/2201FBB7-0403-4A18-A361-CAD5A76A637D) to detect traps. Loot table: [Goblin Loot](RPG://TABLES/0/25321D0A-CBAC-4A6C-944C-C8916049FC45).",
        coordinates: [
            CGPoint(x: 720, y: 80),
            CGPoint(x: 940, y: 80),
            CGPoint(x: 940, y: 280),
            CGPoint(x: 720, y: 280),
        ],
        isShown: false
    )

    // Narrow corridor connecting entrance to the hall
    @MainActor
    static let previewCorridor = MapEntryModel(
        id: UUID.fixture("D4E5F6A7-B8C9-0123-DEF0-234567890123"),
        name: "Corridor",
        content: "A narrow passage. The floor is slippery with moisture. [Thrak the Cruel](RPG://VALUES/0/1527140F-0101-46C3-912E-B02FE0FF7696) was spotted fleeing through here.",
        coordinates: [
            CGPoint(x: 250, y: 600),
            CGPoint(x: 300, y: 600),
            CGPoint(x: 300, y: 550),
            CGPoint(x: 250, y: 550),
        ],
        isShown: true
    )

    // Shadowfen Crossing — fen path
    @MainActor
    static let previewFenPath = MapEntryModel(
        id: UUID.fixture("B3C4D5E6-F7A8-9012-B345-6789012ABCDE"),
        name: "Fen Path",
        content: "A crumbling path through the marsh. [Mira Swiftblade](RPG://VALUES/0/1527140F-0101-46C3-912E-B02FE0FF7696) scouts ahead. Play [Storm over Emberkeep](RPG://AUDIOS/0/00000000-0000-0000-0000-000000000021) for tension.",
        coordinates: [
            CGPoint(x: 50, y: 200),
            CGPoint(x: 400, y: 200),
            CGPoint(x: 400, y: 400),
            CGPoint(x: 50, y: 400),
        ],
        isShown: true
    )

    // Shadowfen Crossing — ancient ruins
    @MainActor
    static let previewAncientRuins = MapEntryModel(
        id: UUID.fixture("C4D5E6F7-A8B9-0123-C456-789012ABCDEF"),
        name: "Ancient Ruins",
        content: "Crumbled walls overgrown with vines. Roll [Quick Strike](RPG://DICE/0/2201FBB7-0403-4A18-A361-CAD5A76A637D) to ambush lurking wraiths. See [Asche der Drachen](RPG://ADVENTURES/0/8C94288B-4CDB-4109-B0AD-75B12530ED84) for the region lore.",
        coordinates: [
            CGPoint(x: 500, y: 100),
            CGPoint(x: 850, y: 100),
            CGPoint(x: 850, y: 350),
            CGPoint(x: 500, y: 350),
        ],
        isShown: false
    )

}

extension MapPinModel {
    // Pins placed at center-points of preview rooms
    @MainActor
    static let previewPins: [MapPinModel] = [
        MapPinModel(
            id: UUID.fixture("E5F6A7B8-C9D0-1234-EF01-345678901234"),
            name: "Goblin Guard",
            color: .red,
            location: CGPoint(x: 150, y: 625),
            size: .normal,
            isShown: true
        ),
        MapPinModel(
            id: UUID.fixture("F6A7B8C9-D0E1-2345-F012-456789012345"),
            name: "Dragon",
            color: .orange,
            location: CGPoint(x: 500, y: 375),
            size: .huge,
            isShown: true
        ),
        MapPinModel(
            id: UUID.fixture("07B8C9D0-E1F2-3456-0123-567890123456"),
            name: "Treasure Chest",
            color: .yellow,
            location: CGPoint(x: 830, y: 180),
            size: .small,
            isShown: false
        ),
        MapPinModel(
            id: UUID.fixture("18C9D0E1-F203-4567-1234-678901234567"),
            name: "Secret Door",
            color: .blue,
            location: CGPoint(x: 275, y: 575),
            size: .tiny,
            isShown: false
        ),
    ]
}
