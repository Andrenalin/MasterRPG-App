// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import RPGResources
import SwiftData

// MARK: Preview

public extension TableRootModel {
    @MainActor
    static let preview: TableRootModel = {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = TableRootModel(container: modelContainer, diceRoot: DiceFactory.root(container: modelContainer), pdfRoot: .preview)
        root.setUp(context: nil, rootControllable: root)
        root.diceRoot.setUp(context: nil, rootControllable: root)
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: TableRootModel = {
        let root = TableRootModel.preview
        let itemController = root.itemController
        let importController = root.importController
        let editController = root.editController
        let gameController = root.gameController
#if DEBUG
        Task { @MainActor in
            let bundle = Resources.bundle
            guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url)
            let _ = try await task.value
            let saveTask = Task { @MainActor in
                editController.setCurrentItem(to: .previewWithData(from: itemController))
            }
            _ = await saveTask.result
            Task.detached {
                await print(itemController.itemDataModel.items.first!.id)
                _ = await gameController.setCurrent(itemId: itemController.itemDataModel.items.first!.id)
            }
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot(diceRoot: DiceRootModel, pdfRoot: PdfRootModel) -> TableRootModel {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = TableRootModel(container: modelContainer, diceRoot: .preview, pdfRoot: .preview)
        root.setUp(context: nil, rootControllable: root)
        return root
    }
#endif

    @MainActor
    static let linkRegisterController = FakeLinkRegisterController()
}

extension TableRootModel: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }

    @MainActor
    public var linkRegisterControllable: LinkRegisterControllable {
        TableRootModel.linkRegisterController
    }
    
    public var gameExportControllable: any ExportControllable {
        exportController
    }
    public var gameImportControllable: any ImportControllable {
        importController
    }
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: TableModel.previewId, typeId: .table)
    @MainActor
    static func previewWithData(from itemController: ItemController) -> ItemRowTreeModel {
        ItemRowTreeModel(itemId: itemController.itemDataModel.items[0], entryId: itemController.itemOrEmpty(for: itemController.itemDataModel.items[0]).entries[0].id, typeId: .table)
    }
}

extension ItemController {
    @MainActor
    static let preview = TableRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = TableRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = TableRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = TableRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = TableRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static var preview = TableRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = TableRootModel.preview.linkController
}

extension GeneratorController {
    @MainActor
    static let previewWithData: GeneratorController = {
        let root = TableRootModel.previewWithData
        let itemController = root.itemController
        let generatorController = GeneratorController(root: root, rootItemId: TableModel.previewId)
#if DEBUG
        Task.detached(priority: .userInitiated) {
            try await Task.sleep(for: .seconds(0.5))
            Task { @MainActor in
                generatorController.genDataModel.rootItemId = itemController.itemDataModel.items[0]
                generatorController.reset()
                _ = generatorController.roleResults()
            }
        }
#endif
        return generatorController
    }()
}

// Example Preview Data

extension TableModel {
    static let previewId = UUID(uuidString: "25321D0A-CBAC-4A6C-944C-C8916049FC45")!
    static let preview = TableModel(
        id: previewId,
        name: "Beutetabelle B",
        description: "W20 — Primitive Humanoide",
        tags: ["Beute", "DS"],
        category: .loot,
        displayState: 0,
        tableType: .dice,
        diceId: UUID(uuidString: "46339863-D29C-4B28-98BC-C6A20D5BCE0E")!,
        entries: [
            .preview,
            .previewLink,
            
            TableEntryModel(
                id: UUID(uuidString: "A86606F6-195B-482F-B198-76161272C4D4")!,
                name: "1",
                content: "Fischgräte, madiges Fleisch o.ä.",
                displayState: 0,
                diceResult: "3"
            ),
            TableEntryModel(
                id: UUID(uuidString: "BED56C0A-E5EA-4B31-8A39-E4ED2339A1A7")!,
                name: "2",
                content: "kaputter Wasserschlauch",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "F0C48BDB-2D5A-4A7F-B9DB-349D2DF7A549")!,
                name: "3",
                content: "Apfelgriebsch, Brotkanten, Knochen o.ä.",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "F6D47E6C-A099-4CB2-964E-FB54F7536587")!,
                name: "4",
                content: "Wasserschlauch",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "A9685B38-65BF-49F2-9CD0-0F3356F1FF85")!,
                name: "5",
                content: "frischer Proviant (erlegtes Kleintier o.ä.)",
                displayState: 0,
                diceResult: nil
            ), TableEntryModel(
                id: UUID(uuidString: "1235BCA3-582F-4609-A92A-A115329E93AA")!,
                name: "6",
                content: "blutige Lumpen",
                displayState: 0,
                diceResult: nil
            ), TableEntryModel(
                id: UUID(uuidString: "CB6EC626-32EE-41CE-8820-FC6CE1278C12")!,
                name: "7",
                content: "Stück Schnur",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "06F78C9C-28FF-4BB1-9A7F-187E314429F0")!,
                name: "8",
                content: "ausgefranste, schmuddelige Decke",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "E589DC7A-51EB-45DE-B8E1-D2B433EA9097")!,
                name: "9",
                content: "verbogenes Stück Draht",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "1E4DBF59-195D-4631-8A9B-7D3A61093FCD")!,
                name: "10",
                content: "bunte Murmel oder Kerzenstummel",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "9DD5CBE7-A601-45B9-BAB9-1D4222EB35AF")!,
                name: "11",
                content: "Feuerstein & Zunder",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "10770123-0C27-4BF4-A7F1-2D44BC1D6FCC")!,
                name: "12",
                content: "Kette aus Zähnen, Schrumpfkopf o.ä.",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "794028DF-B2D2-4FB8-8A2B-AFC6FE1E26F4")!,
                name: "13",
                content: "einfacher Angelhaken ohne Schnur",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "A67BDD59-2374-4F27-BACB-C457523E5C0A")!,
                name: "14",
                content: "([d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E)/2)m modriges Seil",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "F8E9686E-0494-490F-A0BB-B253E7119AA1")!,
                name: "15",
                content: "[d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) bunte, aber wertlose Steine",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "287E67C0-B02C-4CA3-B13A-F138947189A8")!,
                name: "16",
                content: "Edelsteinsplitter ([d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) KM)",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "2619D9CA-7E1D-482C-BBC0-89DDF0690006")!,
                name: "17",
                content: "[d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) KM, [d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) SM",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "76FE2A6B-DE29-484E-BE67-F5375B8ABBC1")!,
                name: "18",
                content: "[d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) KM, [d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) SM, [d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) GM",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID(uuidString: "7B9ADFDD-6CBF-4365-B3C8-85D863E4CF78")!,
                name: "20",
                content: "[d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) Edelsteine (je [d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) GM)",
                displayState: 0,
                diceResult: nil
            ),
        ],
        diceResult: "20"
    )
}

extension TableEntryModel {
    static var previewId: UUID {
        UUID(uuidString: "A86606F6-195B-482F-B198-76161272C4D4") ?? UUID()
    }
    
    static var preview: TableEntryModel {
        TableEntryModel(id: previewId, name: "Unverwundbartrank", content: "(1.000GM) Der Charakter erhält für W20 Runden +20 auf seine Abwehr durch diesen meist roten, flockigen Trank. Dieser Bonus gilt auch bei Schaden, gegen den normalerweise keine Abwehr zulässig ist.")
    }
    
    static var previewLinkId: UUID {
        UUID(uuidString: "55531D39-BBCB-4663-9E23-D37CD3433F88") ?? UUID()
    }
    
    static var previewLink: TableEntryModel {
        TableEntryModel(
            id: previewLinkId, name: "1", content: "this is: [Andrenalin](RPG://TABLES/\(TableModel.previewId)/\(previewId)) a ring"
        )
    }
}
