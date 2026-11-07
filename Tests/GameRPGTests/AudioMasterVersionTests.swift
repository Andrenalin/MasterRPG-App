// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@MainActor
@Suite("Audio master version")
struct AudioMasterVersionTests {
    @Test("A report is dropped when the master's version of the item changes")
    func versionChangeDropsReports() {
        let model = ItemGameModel(itemDataModel: ItemDataModel())
        let itemId = UUID()
        let player = UUID()

        #expect(!model.recordMasterVersion(1, for: itemId))
        model.setPlayerReport(playerId: player, for: itemId)
        #expect(!model.recordMasterVersion(1, for: itemId))
        #expect(model.playerReport(for: itemId) == [player])

        #expect(model.recordMasterVersion(2, for: itemId))
        #expect(model.playerReport(for: itemId).isEmpty)
        #expect(model.masterVersions[itemId] == 2)
    }

    @Test("The reports of another item are kept")
    func otherItemsKeepReports() {
        let model = ItemGameModel(itemDataModel: ItemDataModel())
        let kept = UUID()
        let replaced = UUID()
        let player = UUID()
        model.recordMasterVersion(1, for: kept)
        model.recordMasterVersion(1, for: replaced)
        model.setPlayerReport(playerId: player, for: kept)
        model.setPlayerReport(playerId: player, for: replaced)

        model.recordMasterVersion(5, for: replaced)

        #expect(model.playerReport(for: kept) == [player])
        #expect(model.playerReport(for: replaced).isEmpty)
    }
}
#endif
