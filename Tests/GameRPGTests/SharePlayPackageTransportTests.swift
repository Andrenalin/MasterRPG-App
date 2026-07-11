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

    @Test("master journals file-backed store payloads")
    func masterJournalsFileBackedStorePayloads() {
        let photo = NetworkCodableDataType(id: UUID(), type: .photo, version: 1, data: Data("photo".utf8))
        let audio = NetworkCodableDataType(id: UUID(), type: .audio, version: 1, data: Data("audio".utf8))
        let space = NetworkCodableDataType(id: UUID(), type: .space, version: 1, data: Data("space".utf8))
        let setting = NetworkCodableDataType(id: UUID(), type: .setting, version: 1, data: Data("setting".utf8))

        #expect(MasterController.usesFileJournal(for: photo))
        #expect(MasterController.usesFileJournal(for: audio))
        #expect(MasterController.usesFileJournal(for: space))
        #expect(!MasterController.usesFileJournal(for: setting))
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
