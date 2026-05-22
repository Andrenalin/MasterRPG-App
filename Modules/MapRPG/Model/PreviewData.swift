// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
import PdfRPG
import PhotoRPG
import RPGResources
import TableRPG
import CharacterRPG
import SwiftUI

public extension MapRootModel {
    static let previewValueId = MapModel.previewId

    @MainActor
    static let preview: MapRootModel = {
        var root = MapRootModel(tagController: .preview, audioRoot: .preview, diceRoot: .preview, pdfRoot: .preview, photoRoot: .preview, tableRoot: .preview, characterRoot: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root.tableRoot, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.diceRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.photoRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.pdfRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.audioRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.tableRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.characterRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        //root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: MapRootModel = {
        let root = MapRootModel.preview
        let itemController = root.itemController
        let importController = root.importController
        let editController = root.editController
        let photoCon = root.photoRoot.itemControllable
#if DEBUG
        Task(priority: .userInitiated) {
            let bundle = RPGResources.Resources.bundle
            guard let url = bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url)
            let _ = try await task.value
            Task { @MainActor in
                editController.setCurrentItem(to: ItemRowTreeModel.previewWithData(with: itemController))
            }
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot(audioRoot: AudioRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel) -> MapRootModel {
        let root = MapRootModel(tagController: .preview, audioRoot: .preview, diceRoot: .preview, pdfRoot: .preview, photoRoot: .preview, tableRoot: .preview, characterRoot: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root.tableRoot, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.diceRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.photoRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.pdfRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.audioRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.tableRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.characterRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        return root
    }
#endif
}

@MainActor
extension MapRootModel: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }

    public var gameExportControllable: any ExportControllable {
        exportController
    }
    public var gameImportControllable: any ImportControllable {
        importController
    }
}

// MARK: Preview - Test
extension MapModel {
    static let previewId = UUID(uuidString: "50DFDB6F-E8B1-41A4-A409-911D888119E8")!
    @MainActor
    static let preview = MapModel(
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
        photoId: UUID(uuidString: "F3CA87E3-940B-402F-B059-F09EC602AC52")!,
        width: 1000,
        height: 800,
        mapPins: MapPinModel.previewPins,
        pinScale: 1.0,
        scale: 1.0,
        degrees: 0.0
    )
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
    static let uuid = UUID(uuidString: "14C7502D-2EDF-4457-AE0D-6152DFA8E8DF")!

    func generateModel() -> String {
        """
            MapViewModel(
                id: UUID(uuidString: \"\(id)\")!,
                name: \"\(name)\",
                description:
        \"\"\"
        \(description)
        \"\"\"
        ,
                tags: \(tags),
                entries: \(generateEntries()),
                displayConfig: \(displayConfig.generateModel()),
                photoId: \(generateUUID(for: photoId)),
                width: \(width),
                height: \(height),
                scale: \(scale),
                degrees: \(degrees)
            )
        """
    }

    private func generateUUID(for uuid: UUID?) -> String {
        if let uuid {
            return "UUID(uuidString: \"\(uuid)\")!"
        } else {
            return "nil"
        }
    }

    private func generateEntries() -> String {
        var result = "["
        entries.forEach {
            result.append($0.generateModel() + ",")
        }
        result.append("]")
        return result
    }
}

extension MapEntryModel {
    static let previewId: UUID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!

    // Kept for backward compatibility — aliases the entrance room
    @MainActor
    static var preview: MapEntryModel { previewEntrance }

    // Entrance room — bottom-left area
    @MainActor
    static let previewEntrance = MapEntryModel(
        id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
        name: "Entrance",
        content: "The dungeon entrance. Torches flicker on damp stone walls.",
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
        id: UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!,
        name: "Great Hall",
        content: "A vast pillared hall. Ancient banners hang from the ceiling.",
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
        id: UUID(uuidString: "C3D4E5F6-A7B8-9012-CDEF-123456789012")!,
        name: "Treasure Room",
        content: "Glittering gold fills every corner. Beware the trap floor.",
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
        id: UUID(uuidString: "D4E5F6A7-B8C9-0123-DEF0-234567890123")!,
        name: "Corridor",
        content: "A narrow passage. The floor is slippery with moisture.",
        coordinates: [
            CGPoint(x: 250, y: 600),
            CGPoint(x: 300, y: 600),
            CGPoint(x: 300, y: 550),
            CGPoint(x: 250, y: 550),
        ],
        isShown: true
    )
    func generateModel() -> String {
        """
            EntryViewModel(
                id: UUID(uuidString: \"\(id)\")!,
                name: \"\(name)\",
                description:
        \"\"\"
        \(content)
        \"\"\"
        ,                
                coordinates: \(generateCoords()),
                isShown: \(isShown ? "true" : "false"),
                links: []
            )
        """
    }

    private func generateCoords() -> String {
        coordinates.map { "CGPoint(x: \($0.x), y: \($0.y)), " }.reduce("[") { $0 + $1 } + "]"
    }
}

extension MapPinModel {
    // Pins placed at center-points of preview rooms
    @MainActor
    static let previewPins: [MapPinModel] = [
        MapPinModel(
            id: UUID(uuidString: "E5F6A7B8-C9D0-1234-EF01-345678901234")!,
            name: "Goblin Guard",
            color: .red,
            location: CGPoint(x: 150, y: 625),
            size: .normal,
            isShown: true
        ),
        MapPinModel(
            id: UUID(uuidString: "F6A7B8C9-D0E1-2345-F012-456789012345")!,
            name: "Dragon",
            color: .orange,
            location: CGPoint(x: 500, y: 375),
            size: .huge,
            isShown: true
        ),
        MapPinModel(
            id: UUID(uuidString: "07B8C9D0-E1F2-3456-0123-567890123456")!,
            name: "Treasure Chest",
            color: .yellow,
            location: CGPoint(x: 830, y: 180),
            size: .small,
            isShown: false
        ),
        MapPinModel(
            id: UUID(uuidString: "18C9D0E1-F203-4567-1234-678901234567")!,
            name: "Secret Door",
            color: .blue,
            location: CGPoint(x: 275, y: 575),
            size: .tiny,
            isShown: false
        ),
    ]
}

extension DisplayConfigModel {
    static var testViewModel: DisplayConfigModel {
        DisplayConfigModel(id: UUID(), tileCoordinates: [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.55, y: 0.5),
            CGPoint(x: 0.55, y: 0.55),
            CGPoint(x: 0.5, y: 0.55),
        ], color: .blue, border: DisplayBorderViewModel(id: UUID(), thickness: 10.0))
    }

    func generateModel() -> String {
        """
                DisplayConfigViewModel(
                    id: UUID(uuidString: \"\(id)\")!,
                    tileCoordinates: \(generatePoints()),
                    color: \(CodableColor(color).generateModel()).color,
                    border: \(border.generateModel())
                )
        """
    }

    private func generatePoints() -> String {
        tileCoordinates.map { "CGPoint(x: \($0.x), y: \($0.y)), " }.reduce("[") { $0 + $1 } + "]"
    }
}

extension DisplayBorderViewModel {
    func generateModel() -> String {
        """
                DisplayBorderViewModel(
                    id: UUID(uuidString: \"\(id)\")!,
                    thickness: \(thickness),
                    color: \(CodableColor(color).generateModel()).color
                )
        """
    }
}
