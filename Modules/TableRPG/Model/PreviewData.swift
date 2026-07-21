// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import PdfRPG

// MARK: Preview

public extension TableRootModel {
    @MainActor
    static var preview: TableRootModel { previewFixture() }

    @MainActor
    internal static func previewFixture(
        models: [TableModel] = TableModel.previewFixtures
    ) -> TableRootModel {
        let root = TableRootModel(tagController: .preview, diceRoot: .preview, pdfRoot: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root, spaceRoot: root, tableRoot: root, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.diceRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.pdfRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }
        root.editController.setCurrentItem(to: .preview)
        return root
    }
    
    @MainActor
    static var previewWithData: TableRootModel { previewFixture() }
    
#if DEBUG
    @MainActor
    static func testRoot(diceRoot: DiceRootModel, pdfRoot: PdfRootModel) -> TableRootModel {
        let root = TableRootModel(tagController: .preview, diceRoot: diceRoot, pdfRoot: pdfRoot)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let rootManagerReal = RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root, spaceRoot: root, tableRoot: root, weatherRoot: root)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.diceRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        root.pdfRoot.setUp(context: nil, batchContext: nil, rootManager: rootManagerReal, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManagerReal))
        return root
    }
#endif
}

@MainActor
extension TableRootModel: RootExportControllable {
    public var linkControllable: LinkControllable {
        linkController
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

// Example Preview Data

extension TableModel {
    nonisolated static let previewId = UUID.fixture("25321D0A-CBAC-4A6C-944C-C8916049FC45")
    static let preview = TableModel(
        id: previewId,
        name: "Beutetabelle B",
        description: "W20 — Primitive Humanoide",
        tags: ["Beute", "DS"],
        category: .loot,
        displayState: 0,
        tableType: .dice,
        diceId: DiceRootModel.previewDiceId,
        entries: [
            .preview,
            .previewLink,
            
            TableEntryModel(
                id: UUID.fixture("A86606F6-195B-482F-B198-76161272C4D4"),
                name: "1",
                content: "Fischgräte, madiges Fleisch o.ä.",
                displayState: 0,
                diceResult: "3"
            ),
            TableEntryModel(
                id: UUID.fixture("BED56C0A-E5EA-4B31-8A39-E4ED2339A1A7"),
                name: "2",
                content: "kaputter Wasserschlauch",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("F0C48BDB-2D5A-4A7F-B9DB-349D2DF7A549"),
                name: "3",
                content: "Apfelgriebsch, Brotkanten, Knochen o.ä.",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("F6D47E6C-A099-4CB2-964E-FB54F7536587"),
                name: "4",
                content: "Wasserschlauch",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("A9685B38-65BF-49F2-9CD0-0F3356F1FF85"),
                name: "5",
                content: "frischer Proviant (erlegtes Kleintier o.ä.)",
                displayState: 0,
                diceResult: nil
            ), TableEntryModel(
                id: UUID.fixture("1235BCA3-582F-4609-A92A-A115329E93AA"),
                name: "6",
                content: "blutige Lumpen",
                displayState: 0,
                diceResult: nil
            ), TableEntryModel(
                id: UUID.fixture("CB6EC626-32EE-41CE-8820-FC6CE1278C12"),
                name: "7",
                content: "Stück Schnur",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("06F78C9C-28FF-4BB1-9A7F-187E314429F0"),
                name: "8",
                content: "ausgefranste, schmuddelige Decke",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("E589DC7A-51EB-45DE-B8E1-D2B433EA9097"),
                name: "9",
                content: "verbogenes Stück Draht",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("1E4DBF59-195D-4631-8A9B-7D3A61093FCD"),
                name: "10",
                content: "bunte Murmel oder Kerzenstummel",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("9DD5CBE7-A601-45B9-BAB9-1D4222EB35AF"),
                name: "11",
                content: "Feuerstein & Zunder",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("10770123-0C27-4BF4-A7F1-2D44BC1D6FCC"),
                name: "12",
                content: "Kette aus Zähnen, Schrumpfkopf o.ä.",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("794028DF-B2D2-4FB8-8A2B-AFC6FE1E26F4"),
                name: "13",
                content: "einfacher Angelhaken ohne Schnur",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("A67BDD59-2374-4F27-BACB-C457523E5C0A"),
                name: "14",
                content: "([d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E)/2)m modriges Seil",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("F8E9686E-0494-490F-A0BB-B253E7119AA1"),
                name: "15",
                content: "[d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) bunte, aber wertlose Steine",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("287E67C0-B02C-4CA3-B13A-F138947189A8"),
                name: "16",
                content: "Edelsteinsplitter ([d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) KM)",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("2619D9CA-7E1D-482C-BBC0-89DDF0690006"),
                name: "17",
                content: "[d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) KM, [d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) SM",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("76FE2A6B-DE29-484E-BE67-F5375B8ABBC1"),
                name: "18",
                content: "[d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) KM, [d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) SM, [d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) GM",
                displayState: 0,
                diceResult: nil
            ),
            TableEntryModel(
                id: UUID.fixture("7B9ADFDD-6CBF-4365-B3C8-85D863E4CF78"),
                name: "20",
                content: "[d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) Edelsteine (je [d20](RPG://DICE/46339863-D29C-4B28-98BC-C6A20D5BCE0E) GM)",
                displayState: 0,
                diceResult: nil
            ),
        ],
        diceResult: "20"
    )

    nonisolated static let previewEmptyId = UUID(uuid: (0xB5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    nonisolated static let previewShortListId = UUID(uuid: (0xB5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))

    /// Deterministic fixture for empty-state views.
    @MainActor
    static let previewEmpty = TableModel(
        id: previewEmptyId,
        name: "Empty Table",
        description: "A table fixture with no entries.",
        tags: ["Preview"],
        tableType: .list,
        entries: []
    )

    /// Small deterministic list fixture that keeps snapshot output focused.
    @MainActor
    static let previewShortList = TableModel(
        id: previewShortListId,
        name: "Roadside Encounters",
        description: "Two concise encounter results.",
        tags: ["Preview", "Encounter"],
        tableType: .list,
        entries: [
            TableEntryModel(
                id: UUID(uuid: (0xB5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)),
                name: "1",
                content: "A merchant asks for directions."
            ),
            TableEntryModel(
                id: UUID(uuid: (0xB5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4)),
                name: "2",
                content: "Fresh tracks cross the road."
            )
        ]
    )

    @MainActor
    static var previewFixtures: [TableModel] {
        [preview, previewShortList, previewEmpty]
    }
}

extension TableEntryModel {
    static var previewId: UUID {
        UUID.fixture("A86606F6-195B-482F-B198-76161272C4D4")
    }
    
    static var preview: TableEntryModel {
        TableEntryModel(id: previewId, name: "Unverwundbartrank", content: "(1.000GM) Der Charakter erhält für W20 Runden +20 auf seine Abwehr durch diesen meist roten, flockigen Trank. Dieser Bonus gilt auch bei Schaden, gegen den normalerweise keine Abwehr zulässig ist.")
    }
    
    static var previewLinkId: UUID {
        UUID.fixture("55531D39-BBCB-4663-9E23-D37CD3433F88")
    }
    
    static var previewLink: TableEntryModel {
        TableEntryModel(
            id: previewLinkId, name: "1", content: "this is: [Andrenalin](RPG://TABLES/\(TableModel.previewId)/\(previewId)) a ring"
        )
    }
}

private extension UUID {
    nonisolated static func fixture(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid deterministic preview UUID: \(value)")
        }
        return id
    }
}
