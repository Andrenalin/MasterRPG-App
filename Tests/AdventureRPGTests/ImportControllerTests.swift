// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import DiceRPG
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
@testable import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import RPGResourcesDebug
import Testing
import WeatherRPG

@testable import AdventureRPG

@MainActor
@Suite(.serialized)
struct ImportControllerTests {
    @Test func importingAndValidationRegisterAdventureEntryLinks() async throws {
        // Given / When: import the package through the real module import workflow.
        let root = try await MockRoot.importTestData()
        let linkedEntry = try #require(root.itemController.itemDataModel.items.lazy.compactMap { itemId in
            root.itemController.itemSync(for: itemId).flatMap { item in
                item.entries.first { !LinkReplaceController.links(for: $0.content).isEmpty }
                    .map { (item, $0) }
            }
        }.first)
        let source = ItemRowModel(
            itemId: linkedEntry.0.id,
            entryId: linkedEntry.1.id,
            typeId: .adventure
        )
        let parsedDestinations = Set(LinkReplaceController.links(for: linkedEntry.1.content).map {
            ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module)
        })

        // Then: import populated the outgoing index.
        let importedDestinations = Set(root.linkRegisterController.linksFrom(source: source).map(\.destination))
        #expect(importedDestinations == parsedDestinations)

        // When: simulate an empty/stale register and run the folder validation repair.
        await root.linkRegisterController.resetData()
        for itemId in root.itemController.itemDataModel.items {
            root.linkController.validateLinks(on: itemId)
        }

        // Then: validation rebuilt the same outgoing links.
        let validatedDestinations = Set(root.linkRegisterController.linksFrom(source: source).map(\.destination))
        #expect(validatedDestinations == parsedDestinations)
    }

    @Test func importing() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.importController

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.adventureTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = sut.importUrl(from: url)
        let _ = try await task.value
        #expect(root.itemController.itemDataModel.items.count == 3)
    }

    @Test func mergeSecondImportDoesNotChangeAdventureItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let bundle = ResourcesDebug.bundle
        let url = try #require(bundle.url(forResource: ResourcesDebug.adventureTestData, withExtension: "gmz"))

        let firstImportTask = root.importController.importUrl(from: url)
        let _ = try await firstImportTask.value
        let existingItems = root.itemController.itemDataModel.items.compactMap { itemId in
            root.itemController.itemSync(for: itemId)?.copy()
        }

        let secondImportTask = root.importController.importUrl(from: url)
        let _ = try await secondImportTask.value

        let importedItems = root.itemController.itemDataModel.items.compactMap { itemId in
            root.itemController.itemSync(for: itemId)?.copy()
        }
        #expect(importedItems == existingItems)
    }

    @Test func manualReviewSecondImportDoesNotReportIdenticalItems() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let bundle = ResourcesDebug.bundle
        let url = try #require(bundle.url(forResource: ResourcesDebug.adventureTestData, withExtension: "gmz"))

        let firstImportTask = root.importController.importUrl(from: url)
        let _ = try await firstImportTask.value

        let existingItems = root.itemController.itemDataModel.items.compactMap { itemId in
            root.itemController.itemSync(for: itemId)?.copy()
        }

        let importModel = ItemDataImportModel()
        importModel.importMode = .manual

        let task = root.importController.importUrl(from: url, importModel: importModel)
        let _ = try await task.value

        let reviewModules = importModel.reviewModel?.modules ?? []
        let adventureReviewModule = reviewModules.first { $0.id == .adventure }
        #expect(importModel.isReviewReady)
        #expect(adventureReviewModule?.changedItems.isEmpty ?? true)
        #expect(adventureReviewModule?.addedItems.isEmpty ?? true)
        #expect(adventureReviewModule?.reviewItems.isEmpty ?? true)

        let importedItems = root.itemController.itemDataModel.items.compactMap { itemId in
            root.itemController.itemSync(for: itemId)?.copy()
        }
        #expect(importedItems == existingItems)
    }

    @Test func aggregateRoundTripPreservesTrailingRules() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let ruleID = try #require(UUID(uuidString: "5B9DF034-22F5-45E6-9483-1BA581A25533"))
        let rule = RuleModel.fixture(
            id: ruleID,
            name: "Trailing aggregate rule",
            category: .entry,
            entries: [.fixture(name: "Rule body", content: "A preserved rule payload")]
        )
        root.ruleRoot.itemController.replace(model: rule, isInsert: true)

        let exportIDs = root.exportController.exporting(
            itemIds: ItemModuleIds(ids: [ruleID], module: .rule)
        )
        let output = OutputStream.toMemory()
        output.open()
        defer { output.close() }
        _ = try await root.exportController.export(itemIds: exportIDs, into: output)
        let data = try #require(
            output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data
        )

        try await MockRoot.resetTestData(for: root)
        let input = InputStream(data: data)
        input.open()
        defer { input.close() }
        try await root.importController.importStream(from: input, forceSave: false)

        #expect(Set(root.ruleRoot.itemController.itemDataModel.items) == [ruleID])
        let importedRule = try #require(root.ruleRoot.itemController.itemSync(for: ruleID))
        #expect(importedRule.name == rule.name)
        #expect(importedRule.description == rule.description)
        #expect(importedRule.tags == rule.tags)
        #expect(importedRule.category == rule.category)
        #expect(importedRule.displayState == rule.displayState)
        #expect(importedRule.entries == rule.entries)
        #expect(importedRule.sourceMetadata == rule.sourceMetadata)
        #expect(importedRule.sourcePayload == rule.sourcePayload)
        #expect(importedRule.parentId == rule.parentId)
    }
}
#endif
