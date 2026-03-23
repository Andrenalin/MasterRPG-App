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
    static let preview = MapModel(id: previewId, name: "Mega Dungeon", description: "Heavy Dunegon", tags: ["Master", "Monster", "Hardcore"], category: .dungeon, displayState: 0, entries: [MapEntryModel.preview], photoId: UUID(uuidString: "F3CA87E3-940B-402F-B059-F09EC602AC52")!, width: 1000, height: 800, scale: 1.0, degrees: 0.0)
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
    static let previewId: UUID = UUID()
    @MainActor
    static let preview = MapEntryModel(id: MapEntryModel.previewId, name: "TestEntry", content: "Super view Text", coordinates: [.zero, CGPoint(x: 400, y: 0), CGPoint(x: 400, y: 200)])
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
