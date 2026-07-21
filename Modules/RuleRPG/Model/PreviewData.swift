// @copyright André Trettin

import CoreRPG
import Foundation

public extension RuleRootModel {
    @MainActor
    static let preview: RuleRootModel = {
        let root = RuleRootModel(tagController: .preview)
        let temporaryManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(
            context: nil,
            batchContext: nil,
            rootManager: temporaryManager,
            adventureRootControllable: root,
            linkRegisterController: LinkRegisterController(root: temporaryManager)
        )
        let rootManager = RootManager(anyRoot: root)
        root.setUp(
            context: nil,
            batchContext: nil,
            rootManager: rootManager,
            adventureRootControllable: root,
            linkRegisterController: LinkRegisterController(root: rootManager)
        )
        root.itemController.replace(model: RuleModel.preview, isInsert: true)
        root.editController.setCurrentItem(
            to: ItemRowTreeModel(itemId: RuleModel.preview.id, typeId: .rule)
        )
        return root
    }()

#if DEBUG
    @MainActor
    static func testRoot() -> RuleRootModel {
        let root = RuleRootModel(tagController: .preview)
        let rootManager = RootManager(anyRoot: root)
        root.setUp(
            context: nil,
            batchContext: nil,
            rootManager: rootManager,
            adventureRootControllable: root,
            linkRegisterController: LinkRegisterController(root: rootManager)
        )
        return root
    }
#endif
}

public extension RuleModel {
    nonisolated static let previewID = UUID(
        uuidString: "D1B63D74-354B-49B9-A654-CF6F1B7F8E12"
    ) ?? UUID()

    @MainActor
    static let preview = RuleModel(
        id: previewID,
        name: "Arcane Shield",
        description: "A defensive spell that surrounds its target with protective force.",
        tags: ["Foundry VTT", "Spell", "DS4"],
        category: .rules,
        entries: [
            RuleEntryModel(
                id: UUID(uuidString: "20D0191E-C885-41D8-9106-5A22102D4893") ?? UUID(),
                name: "Casting Time",
                content: "1 action",
                kind: .value
            ),
            RuleEntryModel(
                id: UUID(uuidString: "18AE5F25-210C-4559-9497-69CB40E8E35E") ?? UUID(),
                name: "Effect",
                content: "The target gains **+2 Defense** until the start of its next turn.",
                kind: .text
            )
        ],
        sourceMetadata: RuleSourceMetadata(
            sourceIdentifier: "Compendium.ds4.spells.arcane-shield",
            systemID: "ds4",
            systemTitle: "Dungeon Slayers 4",
            systemVersion: "1.0",
            packageIdentifier: "ds4.spells",
            packageName: "Spells",
            documentID: "arcane-shield",
            documentType: "Item",
            subtype: "spell",
            ruleCategory: "spell"
        )
    )
}

