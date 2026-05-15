// @copyright André Trettin

import Foundation
import os.log
import Observation

public protocol ExportControllable: Sendable {
    var rootManager: RootManager { get }
    var itemControllable: any ItemControllable { get }

    var exportModel: ItemDataExportModel { get }

    @MainActor func exportingAll() -> ItemModuleIds
    @MainActor func exporting(itemIds: ItemModuleIds) -> ItemModuleIds
    func additionalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, counterUpdater: @MainActor (Int?, Bool) async -> Void) async throws -> ItemModuleIds
}

public extension ExportControllable {
    @MainActor var rootExportController: ExportControllable {
        rootManager.adventureRoot.exportControllable
    }
    
    var fileUrlDataController: FileUrlDataController? { itemControllable.fileUrlDataController }

    func exportUrl(isSaveGame: Bool) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let now = dateFormatter.string(from: Date())
        let name = isSaveGame ? "SavedGame.gms" : "Export.gmz"
        return URL.cachesDirectory.appending(path: "\(now)-\(name)")
    }

    @MainActor func exportingAll() -> ItemModuleIds {
        ItemModuleIds(dictionary: [itemControllable.config.module: itemControllable.itemDataModel.items.filter { itemControllable.itemSync(for: $0)?.displayState != 2 }])
    }

    @MainActor func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        itemIds
    }
    
    func additionalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, counterUpdater: @MainActor (Int?, Bool) async -> Void) async throws -> ItemModuleIds {
        itemIds
    }

    @MainActor func createExport(itemIds: ItemModuleIds, into url: URL) -> Task<Void, any Error> {
        let exportController = rootExportController

        return Task.detached(priority: .userInitiated) {
            await self.resetStartState()
            let _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            guard let outputStream = OutputStream(url: url, append: false) else { throw ItemDataExportableError.openError }

            outputStream.open()
            defer { outputStream.close() }

            let itemIds = await self.exporting(itemIds: itemIds)
            await self.updaterExport(itemCount: itemIds.count, increment: false)
            do {
                try outputStream.append(fileHeader: GmzFileHeader(counter: itemIds.count, token: ExportDataToken.counter.rawValue, version: ExportDataToken.version_2024.rawValue))
                _ = try await exportController.export(itemIds: itemIds, into: outputStream, counterUpdater: self.updaterExport(itemCount:increment:))
                await setExportRunning(false)
            } catch {
                await setExportRunning(false)
                throw error
            }
        }
    }
        
    @MainActor
    func setExportRunning(_ isRunning: Bool) async {
        exportModel.isExportRunning = isRunning
    }

    @MainActor func exporting(ids: Set<UUID>) -> ItemModuleIds {
        exporting(itemIds: ItemModuleIds(ids: ids, module: itemControllable.config.module))
    }

    @MainActor func export(ids: ItemModuleIds) -> (Task<Void, any Error>, URL) {
        let url = exportUrl(isSaveGame: false)
        return (createExport(itemIds: ids, into: url), url)
    }

    @MainActor
    func updaterExport(itemCount: Int?, increment: Bool) async {
        if let itemCount {
            exportModel.totalExportingItems = itemCount
        }
        if increment {
            exportModel.exportedItems += 1
        }
    }

    func export(itemIds: ItemModuleIds, into stream: OutputStream, counterUpdater: @MainActor (Int?, Bool) async -> Void) async throws -> ItemModuleIds {

        await logExport(title: "export", count: itemIds.count)

        var updatedIds = try await additionalExport(itemIds: itemIds, stream: stream, counterUpdater: counterUpdater)
        
        try await extract(itemIds: updatedIds, stream: stream) {
            await counterUpdater(nil, true)
        }
        updatedIds.ids.removeValue(forKey: await token())
        await logExport(title: "export after extract", count: updatedIds.count)
        return updatedIds
    }

    private func extract(itemIds: ItemModuleIds, stream outputStream: OutputStream, counterUpdater: () async -> Void) async throws {
        let allIds = itemIds.ids[await token(), default: []]

        await logExport(title: "extract", count: allIds.count)

        let encoder = JSONEncoder()
        let indexModel = ExportIndexModel(index: allIds.startIndex)

        let dataStream = AsyncThrowingStream<ExportStream, Error> { () async throws -> ExportStream? in
            let index = await indexModel.index
            guard index < allIds.endIndex else { return nil }
            let itemId = allIds[index]
            await indexModel.update(index: allIds.index(after: index))
            guard let item = await self.itemControllable.item(for: itemId) else {
                throw ItemDataExportableError.writeError
            }
            return ExportStream(id: itemId, data: try encoder.encode(item))
        }

        let version = itemControllable.itemDataModel.version
        try outputStream.append(fileHeader: GmzFileHeader(counter: allIds.count, token: await token().rawValue, version: version))

        for try await exportData in dataStream {
            if let data = await inlineFiles(for: exportData.id) {
                try outputStream.append(counter: data.count, token: ExportDataToken.file.rawValue)
                try outputStream.write(data: data)
            }
            try outputStream.append(counter: exportData.data.count, token: ExportDataToken.item.rawValue)
            try outputStream.write(data: exportData.data)
            await counterUpdater()
            try Task.checkCancellation()
        }
    }

    func inlineFiles(for itemId: UUID) async -> Data? {
        guard let fileUrlDataController, let item = await itemControllable.item(for: itemId), let fileUrl = item.fileUrl else { return nil }        
        return try? await fileUrlDataController.loadData(for: fileUrl)
    }

    @MainActor
    func token() async -> NetworkModules {
        itemControllable.config.module
    }

    @MainActor
    func progress() async -> (count: Int, total: Int) {
        (exportModel.exportedItems, exportModel.totalExportingItems)
    }

    func logExport(title: String, count: Int) async {
        let token = await token()
        let counter = await progress()
        Logger.exportController.info("\(title, privacy: .public) \(token.token, privacy: .public) currentItems \(count), exportedItems \(counter.count), total: \(counter.total)")
    }

    @MainActor
    func resetStartState() async {
        exportModel.isExportRunning = true
        exportModel.exportedItems = 0
        exportModel.totalExportingItems = 0
    }
}
