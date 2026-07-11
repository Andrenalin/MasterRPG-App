// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import GameRPG

@Suite("SharePlay package transport")
@MainActor
struct SharePlayPackageTransportTests {

    @Test("sender reports the correct total for exact-size chunks")
    func senderReportsCorrectTotalForExactSizeChunks() async {
        let data = Data("abcdefgh".utf8)
        let collector = PackageCollector()
        let sender = SharePlaySingleQueuePackageSender(packageSize: 4) { package in
            await collector.append(package)
        }

        await sender.send(data: data)

        let packages = await collector.values
        #expect(packages.count == 2)
        #expect(packages.map(\.count) == [1, 2])
        #expect(packages.map(\.total) == [2, 2])
        #expect(packages.compactMap(\.data).reduce(Data(), +) == data)
    }

    @Test("receiver reassembles packages by package number")
    func receiverReassemblesPackagesByPackageNumber() {
        let id = UUID()
        let receiver = SharePlayPackageReceiver()
        let first = PackageMessage(uuid: id, count: 1, total: 2, data: Data("abcd".utf8))
        let second = PackageMessage(uuid: id, count: 2, total: 2, data: Data("efgh".utf8))

        #expect(receiver.received(package: second) == nil)
        let result = receiver.received(package: first)

        #expect(result?.data == Data("abcdefgh".utf8))
    }

    @Test("master journals file-backed reveal and store payloads only when bytes are present")
    func masterJournalsFileBackedRevealAndStorePayloadsOnlyWithData() {
        for type in Self.journaledMessageTypes {
            for module in Self.fileBackedModules {
                let withData = Self.message(type: type, module: module, data: Data(module.token.utf8))
                let idOnly = Self.message(type: type, module: module, data: nil)

                #expect(MasterController.usesFileJournal(for: withData), "\(type) \(module) with bytes should use the file journal")
                #expect(!MasterController.usesFileJournal(for: idOnly), "\(type) \(module) without bytes should stay on the normal message path")
            }
        }
    }

    @Test("player send policy journals the same file-backed reveal and store payloads")
    func playerSendPolicyJournalsFileBackedRevealAndStorePayloadsOnlyWithData() {
        for type in Self.journaledMessageTypes {
            for module in Self.fileBackedModules {
                let withData = Self.message(type: type, module: module, data: Data(module.token.utf8))
                let idOnly = Self.message(type: type, module: module, data: nil)

                #expect(PlayerController.usesFileJournal(for: withData), "\(type) \(module) with bytes should use the file journal")
                #expect(!PlayerController.usesFileJournal(for: idOnly), "\(type) \(module) without bytes should stay on the normal message path")
            }
        }
    }
}

private extension SharePlayPackageTransportTests {
    static let fileBackedModules: [NetworkModules] = [.pdf, .audio, .space, .photo]
    static let journaledMessageTypes: [RPGMessageType] = [.reveal, .store]

    static func message(type: RPGMessageType, module: NetworkModules, data: Data?) -> GameNetworkModel {
        GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: type,
            subType: type == .store ? .store : .show,
            gameConfig: GameConfigModel(id: UUID(), state: .started, master: .empty),
            data: NetworkCodableDataType(id: UUID(), type: module, version: 1, data: data)
        )
    }

}

private actor PackageCollector {
    private var storage: [PackageMessage] = []

    var values: [PackageMessage] {
        storage
    }

    func append(_ package: PackageMessage) {
        storage.append(package)
    }
}
#endif
