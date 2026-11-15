// @copyright André Trettin

import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_26 §5.18: a version mismatch is told once per game, not once per app run.
@MainActor
@Suite("Version notices")
struct VersionNoticeResetTests {
    @Test("A claimed notice stays claimed until the notices are reset")
    func claimsAreOnce() {
        let model = GameNetworkControllerModel(name: "Notices")
        let connection = UUID()
        let mismatch = GameVersionMismatch.peerWrites(version: GameNetworkModel.currentVersion + 1)

        #expect(model.claimVersionNotice(for: connection))
        #expect(!model.claimVersionNotice(for: connection))
        #expect(model.claimVersionNoticeToMaster())
        #expect(!model.claimVersionNoticeToMaster())
        #expect(model.claimMismatchReport(mismatch))
        #expect(!model.claimMismatchReport(mismatch))

        model.resetVersionNotices()

        #expect(model.claimVersionNotice(for: connection))
        #expect(model.claimVersionNoticeToMaster())
        #expect(model.claimMismatchReport(mismatch))
    }

    @Test("Stopping the game resets the claims for the next game")
    func stopGameResetsClaims() async {
        let controller = GameNetworkController(
            name: "Notices",
            proxy: true,
            masterBuilder: { _, _ in MasterNetworkControllableMock() },
            playerBuilder: { _, _ in PlayerStoreAbstractionMock() }
        )
        let mismatch = GameVersionMismatch.peerReads(version: GameNetworkModel.currentVersion + 1)
        #expect(controller.model.claimMismatchReport(mismatch))
        #expect(controller.model.claimVersionNoticeToMaster())

        await controller.stopGame()

        #expect(controller.model.claimMismatchReport(mismatch), "the next game reports the mismatch again")
        #expect(controller.model.claimVersionNoticeToMaster())
    }
}
