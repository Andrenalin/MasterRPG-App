// @copyright André Trettin


import Foundation
import Testing

@testable import CoreRPG
@testable import AudioRPG

@MainActor
struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.exportController

        var ids = sut.exportingAll()
        try #require(ids.ids[.audio] != nil)
        #expect(ids.ids[.audio]!.isEmpty)

        let itemId = await root.itemController.addNew(type: .item)
        ids = sut.exportingAll()
        try #require(ids.ids[.audio] != nil)
        #expect(ids.ids[.audio]! == [itemId])

        let newId = await root.itemController.addNew(type: .item)
        let entry = AudioEntryModel(id: UUID(), audioId: newId)
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = sut.exportingAll()
        try #require(ids.ids[.audio] != nil)
        #expect(ids.ids[.audio]!.count == 2)
    }

    @Test func exporting() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        let entry = AudioEntryModel(id: UUID(), audioId: newId)
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .audio))
        var audioIds = ids.ids[.audio]
        try #require(audioIds != nil)
        #expect(audioIds!.count == 2)
        #expect(audioIds!.contains(itemId))
        #expect(audioIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .audio))
        audioIds = ids.ids[.audio]
        try #require(audioIds != nil)
        #expect(audioIds!.count == 2)
        #expect(audioIds!.contains(itemId))
        #expect(audioIds!.contains(newId))
        #expect(!audioIds!.contains(notConnected))
    }

    @Test("Remote URL export includes cached bytes only when requested")
    func remoteURLFileDataExport() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()
        let itemId = await root.itemController.addNew(type: .item)
        let remoteURL = try #require(
            URL(string: "https://example.com/audio/encounter.m4a")
        )
        let fileData = Data("cached remote audio".utf8)
        var importedFileURL = FileUrl(
            fileId: itemId,
            url: remoteURL,
            location: .url,
            module: NetworkModules.audio.token,
            relativeUrl: nil
        )
        importedFileURL.resetData(fileData)
        let fileController = try #require(root.itemController.fileUrlDataController)
        let storedFileURL = try #require(
            try await fileController.createNewFileUrl(
                fileId: itemId,
                unconvertedFileUrl: importedFileURL,
                pathExtension: "m4a"
            )
        )
        root.editController.reset(fileUrl: storedFileURL, itemId: itemId, forceSave: false)

        let withData = try await exportedPayloads(
            root: root,
            itemId: itemId,
            withoutFileData: false
        )
        let withoutData = try await exportedPayloads(
            root: root,
            itemId: itemId,
            withoutFileData: true
        )

        #expect(withData.map(\.token) == [
            ExportDataToken.file.rawValue,
            ExportDataToken.item.rawValue,
        ])
        #expect(withData.first?.data == fileData)
        #expect(withoutData.map(\.token) == [ExportDataToken.item.rawValue])

        let exportedItem = try JSONDecoder().decode(
            AudioModel.self,
            from: try #require(withoutData.first?.data)
        )
        #expect(exportedItem.fileUrl?.location == .url)
        #expect(exportedItem.fileUrl?.rawUrl == remoteURL)
        #expect(exportedItem.fileUrl?.data == nil)

        try? FileManager.default.removeItem(
            at: fileController.remoteCacheURL(for: storedFileURL)
        )
        await root.itemController.resetData()
    }
}

private struct ExportPayload {
    let token: Int
    let data: Data
}

@MainActor
private func exportedPayloads(
    root: AudioRootModel,
    itemId: UUID,
    withoutFileData: Bool
) async throws -> [ExportPayload] {
    let stream = OutputStream.toMemory()
    stream.open()
    defer { stream.close() }

    let exportModel = ItemDataExportModel()
    exportModel.exportWithoutFileData = withoutFileData
    _ = try await root.exportController.export(
        itemIds: ItemModuleIds(ids: [itemId], module: .audio),
        into: stream,
        exportModel: exportModel
    )

    let data = try #require(
        stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data
    )
    let input = InputStream(data: data)
    input.open()
    defer { input.close() }

    let moduleHeader = try input.readHeader()
    #expect(moduleHeader.counter == 1)
    #expect(moduleHeader.token == NetworkModules.audio.rawValue)

    var payloads: [ExportPayload] = []
    while input.hasBytesAvailable {
        let (size, token) = try input.readItemHeader()
        payloads.append(
            ExportPayload(
                token: token,
                data: try input.readData(size: size)
            )
        )
    }
    return payloads
}
