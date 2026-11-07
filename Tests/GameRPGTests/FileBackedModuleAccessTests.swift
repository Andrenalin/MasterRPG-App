// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import GameRPG

@MainActor
@Suite("File-backed module access")
struct FileBackedModuleAccessTests {
    @Test("Photo, Pdf and Space resolve to their own access, other modules to none")
    func resolvesByType() async throws {
        let root = try await MockRoot.createGameRoot()

        #expect(FileBackedModuleAccess.access(for: .photo, in: root)?.module == .photo)
        #expect(FileBackedModuleAccess.access(for: .pdf, in: root)?.module == .pdf)
        #expect(FileBackedModuleAccess.access(for: .space, in: root)?.module == .space)
        for module in [NetworkModules.audio, .map, .table, .weather, .value, .dice] {
            #expect(FileBackedModuleAccess.access(for: module, in: root) == nil)
        }
    }

    @Test("A list subtype resolves to the module that carries it")
    func resolvesByListSubType() async throws {
        let root = try await MockRoot.createGameRoot()

        #expect(FileBackedModuleAccess.access(forListSubType: .photoList, in: root)?.module == .photo)
        #expect(FileBackedModuleAccess.access(forListSubType: .pdfList, in: root)?.module == .pdf)
        #expect(FileBackedModuleAccess.access(forListSubType: .spaceList, in: root)?.module == .space)
        #expect(FileBackedModuleAccess.access(forListSubType: .generic, in: root) == nil)
    }

    @Test("Only Photo and Space sharing can be switched off")
    func sharingFlags() async throws {
        let root = try await MockRoot.createGameRoot()
        let off = GameFeatureModel(audioSharing: false, photoSharing: false, spaceSharing: false)

        #expect(FileBackedModuleAccess.access(for: .photo, in: root)?.isSharingEnabled(off) == false)
        #expect(FileBackedModuleAccess.access(for: .space, in: root)?.isSharingEnabled(off) == false)
        #expect(FileBackedModuleAccess.access(for: .pdf, in: root)?.isSharingEnabled(off) == true)
        #expect(FileBackedModuleAccess.access(for: .photo, in: root)?.isSharingEnabled(GameFeatureModel()) == true)
    }

    @Test("The master version round-trips through the access")
    func masterVersionRoundTrip() async throws {
        let root = try await MockRoot.createGameRoot()
        let access = try #require(FileBackedModuleAccess.access(for: .photo, in: root))
        let itemId = UUID()
        let masterId = UUID()
        #expect(access.masterVersion(itemId, masterId) == nil)

        access.setMasterVersion(itemId, 7, masterId)

        #expect(access.masterVersion(itemId, masterId) == 7)
    }

    @Test("A report list is recognized only in its exact module envelope")
    func reportListEnvelope() {
        let config = GameConfigModel(id: UUID(), state: .started, master: .empty)
        func message(_ type: RPGMessageType, _ subType: RPGMessageActionType, _ module: NetworkModules) -> GameNetworkModel {
            GameNetworkModel(
                counter: 1,
                proxyCounter: 0,
                type: type,
                subType: subType,
                gameConfig: config,
                data: NetworkCodableDataType(id: UUID(), type: module, version: 1, data: nil)
            )
        }

        #expect(message(.update, .photoList, .photo).isReportListEnvelope)
        #expect(message(.update, .pdfList, .pdf).isReportListEnvelope)
        #expect(message(.update, .spaceList, .space).isReportListEnvelope)
        #expect(message(.update, .audioList, .audio).isReportListEnvelope)
        #expect(!message(.reveal, .photoList, .photo).isReportListEnvelope)
        #expect(!message(.update, .photoList, .pdf).isReportListEnvelope)
        #expect(!message(.update, .generic, .photo).isReportListEnvelope)
    }
}
#endif
