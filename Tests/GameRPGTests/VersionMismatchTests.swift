// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §5.9: an envelope of another wire version used to be dropped with a
/// log line while both sides looked connected.
@Suite("Version mismatch")
@MainActor
struct VersionMismatchTests {
    private func envelope(version: Int) -> Data {
        Data(#"{"version": \#(version), "timestamp": 1, "counter": 1}"#.utf8)
    }

    @Test("An envelope of another version is recognised, an undecodable frame is not")
    func detection() {
        let older = GameNetworkModel.currentVersion - 1
        let newer = GameNetworkModel.currentVersion + 1
        #expect(GameVersionMismatch.detect(in: envelope(version: older)) == .peerWrites(version: older))
        #expect(GameVersionMismatch.detect(in: envelope(version: newer)) == .peerWrites(version: newer))
        #expect(GameVersionMismatch.detect(in: envelope(version: GameNetworkModel.currentVersion)) == nil)
        #expect(GameVersionMismatch.detect(in: Data("not json".utf8)) == nil)
        #expect(GameVersionMismatch.detect(in: nil) == nil)
    }

    @Test("A notice names the version the peer reads, and says who has to update")
    func notice() {
        let newer = GameNetworkModel.currentVersion + 1
        let older = GameNetworkModel.currentVersion - 1
        let fromNewer = Data(#"{"incompatibleNotice": \#(newer)}"#.utf8)
        let fromOlder = Data(#"{"incompatibleNotice": \#(older)}"#.utf8)
        #expect(GameVersionMismatch.detect(in: fromNewer) == .peerReads(version: newer))
        #expect(GameVersionMismatch.detect(in: fromNewer)?.thisDeviceNeedsUpdate == true)
        #expect(GameVersionMismatch.detect(in: fromOlder)?.thisDeviceNeedsUpdate == false)
        #expect(GameVersionMismatch.detect(in: GameVersionNotice().encodeData()) == nil)
    }

    @Test("The master tells the person and answers the player once")
    func masterSide() async throws {
        let env = try await NetworkStoreTestEnvironment.create()
        let connectionId = UUID()
        let frame = envelope(version: GameNetworkModel.currentVersion - 1)

        await env.networkController.masterReceived(data: frame, for: connectionId)
        await env.networkController.masterReceived(data: frame, for: connectionId)

        #expect(env.masterDelegateSpy.incompatibleMismatches == [.peerWrites(version: GameNetworkModel.currentVersion - 1)])
        #expect(env.masterNetworkSpy.calledSendResponseId == 1)
        #expect(env.masterNetworkSpy.sendResponseData is GameVersionNotice)
        #expect(env.masterDelegateSpy.calledReceived == 0)
    }

    @Test("The player tells the person and answers the master once")
    func playerSide() async throws {
        let env = try await NetworkStoreTestEnvironment.create()
        let frame = envelope(version: GameNetworkModel.currentVersion + 1)

        await env.networkController.playerReceived(data: frame)
        await env.networkController.playerReceived(data: frame)

        #expect(env.playerDelegateSpy.incompatibleMismatches == [.peerWrites(version: GameNetworkModel.currentVersion + 1)])
        #expect(env.playerNetworkSpy.calledRequest == 1)
        #expect(env.playerNetworkSpy.requestData is GameVersionNotice)
    }

    @Test("A notice is shown but not answered, so two builds never ping-pong")
    func noticeIsNotAnswered() async throws {
        let env = try await NetworkStoreTestEnvironment.create()
        let notice = Data(#"{"incompatibleNotice": \#(GameNetworkModel.currentVersion + 1)}"#.utf8)

        let masterEnv = try await NetworkStoreTestEnvironment.create()
        await env.networkController.playerReceived(data: notice)
        await masterEnv.networkController.masterReceived(data: notice, for: UUID())

        #expect(env.playerDelegateSpy.incompatibleMismatches.count == 1)
        #expect(masterEnv.masterDelegateSpy.incompatibleMismatches.count == 1)
        #expect(env.playerNetworkSpy.calledRequest == 0)
        #expect(masterEnv.masterNetworkSpy.calledSendResponseId == 0)
    }

    @Test("The game log of this device shows the update hint")
    func logNote() async throws {
        let env = try await LinkedGameEnvironment.create()
        await env.master.incompatibleVersion(.peerWrites(version: GameNetworkModel.currentVersion + 1))
        let notes = env.masterRoot.logGameController.logModels.compactMap(\.note)
        #expect(notes.count == 1)
    }
}
#endif
