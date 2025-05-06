// @copyright André Trettin

import AndrenalinKit
import RPGDie
import Foundation
import RPGAudios
import RPGPdfs
import RPGPhotos
import RPGResources
import RPGTables
import RPGValues
internal import SwiftUICore

public extension MapRoot {
    static let previewValueId = MapModel.previewId

    @MainActor
    static let preview: MapRoot = {
        var root = MapRoot(context: nil, audioRoot: .preview, diceRoot: .preview, pdfRoot: .preview, photoRoot: .preview, tableRoot: .preview, valueRoot: .preview)
        root.setRootControllable(root)
        //root.editController(type: .main).setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: MapRoot = {
        let root = MapRoot.preview
        let itemController = root.itemController
        let importController = root.importController
        let editController = root.editController(type: .main)
        let photoCon = root.photoRoot.itemControllable
#if DEBUG
        Task.detached(priority: .userInitiated) {
            let bundle = Resources.bundle
            guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
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
    static func testRoot(audioRoot: AudioRoot, diceRoot: DiceRoot, pdfRoot: PdfRoot, photoRoot: PhotoRoot, tableRoot: TableRoot, valueRoot: ValueRoot) -> MapRoot {
        let root = MapRoot(context: nil, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, valueRoot: valueRoot)
        root.setRootControllable(root)
        return root
    }
#endif

    @MainActor
    static let linkRegisterController = FakeLinkRegisterController()
}

extension MapRoot: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
    
    @MainActor public var linkRegisterControllable: LinkRegisterControllable {
        MapRoot.linkRegisterController
    }
    
    public var gameExportControllable: any ExportControllable {
        gameController.exportController
    }
    public var gameImportControllable: any ImportControllable {
        gameController.importController
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
    static let preview = MapRoot.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = MapRoot.preview.editController(type: .main)
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static let preview = MapRoot.preview.gameController
}

extension ImportController {
    @MainActor
    static let preview = MapRoot.preview.importController
}

extension ExportController {
    @MainActor
    static let preview = MapRoot.preview.exportController
}

extension ListController {
    @MainActor
    static let previewTabId = UUID()
    
    @MainActor
    static let preview = MapRoot.preview.listController(tabId: previewTabId)
}

extension ListModel {
    @MainActor
    static var preview = ListController.preview.model
}

extension ViewController {
    @MainActor
    static let preview = MapRoot.preview.viewController
}

extension LinkController {
    @MainActor
    static let preview = MapRoot.preview.linkController
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
