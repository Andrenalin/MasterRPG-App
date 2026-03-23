// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RPGResources
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG

public extension AdventureRootModel {
    @MainActor
    static let preview: AdventureRootModel = {
        let root = AdventureRootModel(tagController: .preview, audioRoot: .preview, diceRoot: .preview, generatorRoot: nil, mapRoot: .preview, pdfRoot: .preview, photoRoot: .preview, spaceRoot: .preview, tableRoot: .preview, characterRoot: .preview, weatherRoot: .preview)
        let rootManager = RootManager(adventureRoot: root, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root.mapRoot, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root.spaceRoot, tableRoot: root.tableRoot, weatherRoot: root.tableRoot)
        root.setUp(root: rootManager, context: nil, batchContext: nil)
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: AdventureRootModel = {
        let root = AdventureRootModel.preview
        let importController = root.importController
        let editController = root.editController
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
                editController.setCurrentItem(to: .previewWithData)
            }

        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot(audioRoot: AudioRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel) -> AdventureRootModel {
        let root = AdventureRootModel(tagController: .preview, audioRoot: audioRoot, diceRoot: diceRoot, generatorRoot: nil, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, characterRoot: characterRoot, weatherRoot: weatherRoot)
        let rootManager = RootManager(adventureRoot: root, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root.mapRoot, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root.spaceRoot, tableRoot: root.tableRoot, weatherRoot: root.tableRoot)
        root.setUp(root: rootManager, context: nil, batchContext: nil)
        root.editController.setCurrentItem(to: .preview)
        return root
    }
#endif
}

// MARK: Preview - Test
extension AdventureModel {
    static let previewId = UUID(uuidString: "5F6D6D52-3DDB-4B20-8D45-DFB543799417")!
    static let preview = testViewModel
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

extension UUID {
    static let previewId = UUID(uuidString: "70E57E66-3FCE-4E8E-B032-5C79A2322EB8")!
    static let previewEntryId = UUID(uuidString: "70E57E66-3FCE-4E8E-B032-5C79A2322EB8")!
}

extension AdventureModel {
    
    static let uuid = UUID(uuidString: "5F6D6D52-3DDB-4B20-8D45-DFB543799417")!
    static let entryUuid = UUID()
    static let testViewModel = AdventureModel(
        id: uuid,
        name: "Das Geheimnis der Goblinburg",
        description: "DS, F2G04, Stufen 1-4, Das Geheimnis der Goblinburg von Sphärenwanderer\n\nVöllig überraschend kam eine Gruppe von Goblins, die von einigen Hobgoblins angeführt werden, aus dem Nichts und besetzte die kleine Festung des örtlichen Dorfes. Von dem Herrscher fehlt seitdem jegliche Spur. Nun werden Helden gesucht, die die Eindringlinge vertreiben.\n\nEP: Pro Raum 1EP; (besiegte Gegner EP/ SC) EP; Geheimnis gelüftet: 20 EP, Für das Abenteuer 25 EP",
        tags: ["DS", "1-4", "Dungeon", "D2G", "Fan2Go"],
        photoId: UUID(uuidString: "F5AC90DF-36F2-4151-B283-F0CF9D0BAC35")!,
        entries: [
            AdventureEntryModel(id: entryUuid, name: "Ergeschoss", content: "Erster Raum")
        ]
    )
    
    static let uuid2 = UUID(uuidString: "8C94288B-4CDB-4109-B0AD-75B12530ED84")!
    static let testViewModel2 = AdventureModel(
        id: uuid2,
        name: "Asche der Drachen",
        description: "DS, D2G16, Stufen 5-8, Die Asche der Drachen, C. Kennig\n\nDer zasarische Nekromant Muhar Al’Azzrak folgt einer alten Spur und hat sich Zugang zur Gruft des Freiritters Sandor verschafft, die sich auf dem Friedhof von Crimlak befindet. Dabei entdeckte ihn die Helianovizin Kalinda, die der Zasare aber überwältigen konnte.\n\nDie Charaktere befinden sich nach Sonnenuntergang in Crimlak, vorzugsweise in einem der drei Gasthäuser.\nBruder Irdin, ein greiser Mönch aus Kloster Sonntau, betritt keuchend und mit gehetztem Blick das Gasthaus, blickt sich kurz um und kommt schließlich entschlossenen Schrittes auf die Charaktere zu:\n“Verzeiht, dass ich Euch störe, doch Kloster Sonntau braucht Euren Rat. Kalinda, eine junge Novizin unseres kleinen Ordens, war heute Nachmittag zum Friedhof gegangen und kehrte nicht wieder.”\n\n“Als der Sonnenuntergang nahte, machte ich mich auf, nach der Kleinen zu suchen. Ich kam zum Friedhof und ging den Hauptweg entlang, als ich auf einmal eine offene Gruft vor mir entdeckte! Ich bin sofort hierher gerannt, so schnell mich meine alten Füße tragen konnten.”\n\n“Ich fürchte, der Geist von Freiritter Sandor hat sich erhoben, seine Gruft geöffnet und Kalinda in sein kaltes Grab gezerrt! Jemand muss nachsehen - bitte, rettet Kalinda aus den Fängen des Geisterritters, bevor es zu spät ist!”\nAuch wenn Irdin mit seiner Vermutung vom auferstandenen Freitritter Sandor völlig falsch liegt, sollten die Charaktere seiner Bitte nachkommen und sich umgehend auf den Weg machen. Irdin kann den genauen Weg zur Gruft beschreiben, wird aber in der Nacht selbst den Friedhof nicht mehr betreten, sondern im Kloster auf die Charaktere und Kalinda warten.\nTraut man sich erst bei Tagesanbruch, hat Muhar inzwischen alle seine Skelette bei Raum 9 verloren und lauert nun versteckt auf dem Friedhof, in der Hoffnung, dass andere in die Gruft gehen und für ihn die Drachenmaulfalle unschädlich machen.",
        tags: ["DS", "5-8", "Dungeon", "D2G", "Original"],
        photoId: UUID(uuidString: "2201FBB7-0403-4A18-A361-CAD5A76A677D")!,
        entries: [
            AdventureEntryModel(id: entryUuid, name: "Ergeschoss", content: "Erster Raum")
        ]
    )
    
    static let uuid3 = UUID()
    static let testViewModel3 = AdventureModel(id: uuid3, name: "New Image", description: "3rd A new Dungeon")
}
