// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AudioRPG

@MainActor
struct SheetControllerTests {
    @Test func audioSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.item)
        #expect(model.source.itemId == itemId)
        #expect(model.canAdd == false)
        #expect(model.showHeader == false)
    }

    @Test func audioSheetWithAudioInline() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        let item = root.itemController.itemOrEmpty(for: itemId!)

        let rootManager = RootManager(anyRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        if item.hasAudio {
            let audioInline = model.entries.first(where: { $0.sheetType == SheetModelType.audioInline })
            #expect(audioInline != nil)
        }
    }

    @Test func audioSheetEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)

        #expect(model.entries.count >= 0)
        for entry in model.entries {
            if entry.sheetType == SheetModelType.audioInline {
                #expect(entry.level == 0)
            }
        }
    }

    @Test func audioSheetTrackEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let entries = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 0, isShown: true)

        for entry in entries {
            #expect(entry.sheetType == SheetModelType.audioInline)
        }
    }

    @Test func audioSheetWithLinks() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let entries = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 0, isShown: true)

        for entry in entries {
            for linkedSheet in entry.entries {
                #expect(linkedSheet.isShown == false)
                #expect(linkedSheet.level == 1)
            }
        }
    }

    @Test func audioSheetIsShownPropagation() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let modelShown = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func audioSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let entries = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 25, isShown: true)
        #expect(entries.isEmpty)

        let entriesBeforeLimit = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 24, isShown: true)
        #expect(entriesBeforeLimit.count >= 0)
    }

    @Test func audioSheetDestination() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.map)
        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: destination, level: 1, isShown: false)

        #expect(model.destination.itemId == destination.itemId)
    }
}
