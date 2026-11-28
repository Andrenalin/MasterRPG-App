// @copyright André Trettin

import AppIntents
import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import Testing

@testable import TableRPG

/// CODE_AUDIT_Since_3.0.1 §9.1: the bodies the twelve modules' intents copied now live in CoreRPG
/// and look the item up through the entity's `defaultQuery`.
@Suite("Shared intent bodies")
@MainActor
struct ItemIntentSupportTests {
    private func makeRoot() -> TableRootModel {
        TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
    }

    private func addTable(_ root: TableRootModel, name: String) async throws -> TableEntity {
        let id = await root.itemController.addNew(type: .item)
        root.editController.reset(name: name, itemId: id, forceSave: false)
        let model = try #require(root.itemController.itemSync(for: id))
        return TableEntity(root: root, model: model)
    }

    @Test("The Update body changes the item and returns the re-read entity")
    func updateReturnsChangedEntity() async throws {
        let root = makeRoot()
        let intent = UpdateTableIntent()
        intent.target = try await addTable(root, name: "Loot")

        let first = try await updateIntentTarget(intent.$target, prompt: TableIntentSupport.targetPrompt, name: "Treasure", description: nil, addTags: ["gold"], removeTags: nil, in: root)
        #expect(first.changed)
        #expect(first.entity.name == "Treasure")
        #expect(first.entity.tags == ["gold"])

        let second = try await updateIntentTarget(intent.$target, prompt: TableIntentSupport.targetPrompt, name: "Treasure", description: nil, addTags: ["gold"], removeTags: nil, in: root)
        #expect(!second.changed)
        #expect(second.entity.name == "Treasure")
    }

    @Test("A target deleted since it was cached asks for the target again")
    func missingTargetAsksAgain() async throws {
        let root = makeRoot()
        let intent = UpdateTableIntent()
        intent.target = TableEntity(root: root, model: TableModel(id: UUID(), name: "Gone", entries: []))

        #expect(throws: (any Error).self) {
            try requiredIntentModel(intent.$target, prompt: TableIntentSupport.targetPrompt, in: root)
        }
        await #expect(throws: (any Error).self) {
            try await reindexedIntentTarget(intent.$target, prompt: TableIntentSupport.targetPrompt, in: root)
        }
    }

    @Test("The re-read after a write carries the change")
    func reindexedTargetIsCurrent() async throws {
        let root = makeRoot()
        let intent = AddTableRowIntent()
        let entity = try await addTable(root, name: "Loot")
        intent.target = entity
        root.editController.add(entry: TableEntryModel(id: UUID(), name: "Ruby", content: ""), itemId: entity.id, forceSave: true)

        let updated = try await reindexedIntentTarget(intent.$target, prompt: TableIntentSupport.targetPrompt, in: root)
        #expect(updated.id == entity.id)
        let model = try requiredIntentModel(intent.$target, prompt: TableIntentSupport.targetPrompt, in: root)
        #expect(model.entries.map(\.name) == ["Ruby"])
    }

    @Test("An Open intent made for donation carries its target")
    func openingSetsTarget() async throws {
        let root = makeRoot()
        let entity = try await addTable(root, name: "Loot")

        #expect(OpenTableIntent.opening(entity).target.id == entity.id)
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            #expect(OpenTableSchemaIntent.opening(entity).target.id == entity.id)
        }
        #expect(root.siriOpenIntent(for: entity.id) != nil)
        #expect(root.siriOpenIntent(for: UUID()) == nil)
    }
}
