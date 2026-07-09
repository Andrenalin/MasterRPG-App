// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import DiceRPG
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
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
}
#endif
