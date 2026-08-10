// @copyright André Trettin

import Foundation
import os.log
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public protocol ExportControllable: Sendable {
    var hubControllable: any RootExportControllable { get }
    var itemControllable: any ItemControllable { get }

    @MainActor func exportingAll() -> ItemModuleIds
    @MainActor func exporting(itemIds: ItemModuleIds) -> ItemModuleIds
    func additionalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds
    func finalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds
}

public extension ExportControllable {
    // Overwritten in specific
    @MainActor func exportingAll() -> ItemModuleIds {
        ItemModuleIds(dictionary: [itemControllable.config.module: itemControllable.itemDataModel.items.filter { itemControllable.itemSync(for: $0)?.displayState != 2 }])
    }

    @MainActor func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        itemIds
    }

    func additionalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds {
        itemIds
    }

    func finalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds {
        itemIds
    }

    // MARK: - Utilities

    @MainActor var rootExportController: ExportControllable {
        hubControllable.exportControllable
    }

    @MainActor var rootImportController: any ImportControllable {
        hubControllable.importControllable
    }

    var fileUrlDataController: FileUrlDataController? { itemControllable.fileUrlDataController }

    func exportUrl(isSaveGame: Bool, adventureTitle: String? = nil) -> URL {
        let now = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.omitted))
        if isSaveGame, let sanitized = adventureTitle?.sanitizedFileNameComponent, !sanitized.isEmpty {
            return URL.cachesDirectory.appending(path: "\(sanitized)-\(now).gms")
        }
        let name = isSaveGame ? "SavedGame.gms" : "Export.gmz"
        return URL.cachesDirectory.appending(path: "\(now)-\(name)")
    }

    @MainActor func exporting(ids: Set<UUID>) -> ItemModuleIds {
        exporting(itemIds: ItemModuleIds(ids: ids, module: itemControllable.config.module))
    }

    @MainActor func exportingFolder(results: inout Set<UUID>) -> Set<UUID> {
        // Phase 1: promote folders bottom-up — a folder is promoted when ALL its valid children are in results.
        // Processing bottom-up via queue ensures a promoted inner folder triggers its parent check.
        var queue: [UUID] = Array(results)
        while !queue.isEmpty {
            let id = queue.removeLast()
            guard let item = itemControllable.itemSync(for: id),
                  let parentId = item.parentId,
                  !results.contains(parentId),
                  let parent = itemControllable.itemSync(for: parentId),
                  parent.isFolder else { continue }
            let validChildIds = parent.entries.map { $0.childId }.filter { itemControllable.itemSync(for: $0) != nil }
            guard validChildIds.allSatisfy({ results.contains($0) }) else { continue }
            results.insert(parentId)
            queue.append(parentId)
        }
        // Phase 2: walk ancestor folders not yet promoted → partial export
        var partialFolderIds: Set<UUID> = []
        var seen: Set<UUID> = results
        var ancestorQueue: [UUID] = Array(results)
        while !ancestorQueue.isEmpty {
            let id = ancestorQueue.removeLast()
            guard let item = itemControllable.itemSync(for: id),
                  let parentId = item.parentId,
                  !seen.contains(parentId),
                  let parent = itemControllable.itemSync(for: parentId),
                  parent.isFolder else { continue }
            seen.insert(parentId)
            partialFolderIds.insert(parentId)
            ancestorQueue.append(parentId)
        }
        return partialFolderIds
    }

    func logExport(title: String, count: Int) async {
        let module = await MainActor.run { itemControllable.config.module }
        Logger.exportController.info("\(title, privacy: .public) \(module.token, privacy: .public) count: \(count)")
    }

    func logExport(title: String, count: Int, exportModel: ItemDataExportModel) async {
        let (module, exportedItems, totalItems) = await MainActor.run {
            (itemControllable.config.module, exportModel.exportedItems, exportModel.totalExportingItems)
        }
        Logger.exportController.info("\(title, privacy: .public) \(module.token, privacy: .public) currentItems \(count), exportedItems \(exportedItems), total: \(totalItems)")
    }

    // MARK: - Exporters

    // Save Game / normal export
    @MainActor func createExport(itemIds: ItemModuleIds, into url: URL, exportModel: ItemDataExportModel) -> Task<Void, any Error> {
        let exportController = rootExportController

        return Task.detached(priority: .userInitiated) {
            let _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            guard let outputStream = OutputStream(url: url, append: false) else { throw ItemDataExportableError.openError }

            outputStream.open()
            defer { outputStream.close() }

            await MainActor.run {
                exportModel.isExportRunning = true
                exportModel.exportedItems = 0
                exportModel.totalExportingItems = 0
            }

            let itemIds = await MainActor.run {
                let ids = self.exporting(itemIds: itemIds)
                exportModel.totalExportingItems = ids.count
                return ids
            }

            do {
                try outputStream.append(fileHeader: GmzFileHeader(counter: itemIds.count, token: ExportDataToken.counter.rawValue, version: ExportDataToken.version_2024.rawValue))
                _ = try await exportController.export(itemIds: itemIds, into: outputStream, exportModel: exportModel)
                await MainActor.run { exportModel.isExportRunning = false }
            } catch {
                await MainActor.run { exportModel.isExportRunning = false }
                throw error
            }
        }
    }

    // Game direct and Adventure for all other modules export
    func export(itemIds: ItemModuleIds, into stream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds {
        await logExport(title: "export", count: itemIds.count, exportModel: exportModel)

        var updatedIds = try await additionalExport(itemIds: itemIds, stream: stream, exportModel: exportModel)

        try await extract(itemIds: updatedIds, stream: stream, exportModel: exportModel)
        let module = await token()
        updatedIds.ids.removeValue(forKey: module)
        updatedIds.partialIds.removeValue(forKey: module)
        updatedIds = try await finalExport(
            itemIds: updatedIds,
            stream: stream,
            exportModel: exportModel
        )
        await logExport(title: "export after extract", count: updatedIds.count, exportModel: exportModel)
        return updatedIds
    }

    // Convenience for game networking exports — no progress tracking needed
    func export(itemIds: ItemModuleIds, into stream: OutputStream) async throws -> ItemModuleIds {
        let exportModel = await MainActor.run { ItemDataExportModel() }
        return try await export(itemIds: itemIds, into: stream, exportModel: exportModel)
    }

    // List Selection & Setting export
    @MainActor func export(ids: ItemModuleIds, exportModel: ItemDataExportModel) -> (Task<Void, any Error>, URL) {
        let url = exportUrl(isSaveGame: false)
        return (createExport(itemIds: ids, into: url, exportModel: exportModel), url)
    }

    private func extract(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws {
        let module = await token()
        let fullIds = itemIds.ids[module, default: []]
        let partialIds = itemIds.partialIds[module, default: []]
        let allIds = fullIds + partialIds

        await logExport(title: "extract", count: allIds.count, exportModel: exportModel)

        let version = itemControllable.itemDataModel.version
        try outputStream.append(fileHeader: GmzFileHeader(counter: allIds.count, token: module.rawValue, version: version))

        for itemId in allIds {
            try Task.checkCancellation()
            guard let item = await self.itemControllable.item(for: itemId, fullIds: fullIds, partialIds: partialIds) else {
                throw ItemDataExportableError.writeError
            }
            // Models may be @MainActor-isolated; encode on the main actor so the
            // Codable implementation (wire format) stays untouched.
            let data = try await MainActor.run { try JSONEncoder().encode(item) }

            if await !exportModel.exportWithoutFileData, let fileData = await inlineFiles(for: itemId) {
                try outputStream.append(counter: fileData.count, token: ExportDataToken.file.rawValue)
                try outputStream.write(data: fileData)
            }
            try outputStream.append(counter: data.count, token: ExportDataToken.item.rawValue)
            try outputStream.write(data: data)
            await MainActor.run { exportModel.exportedItems += 1 }
            await Task.yield()
        }
    }

    @MainActor private func inlineFiles(for itemId: UUID) async -> Data? {
        guard let fileUrlDataController, let item = await itemControllable.item(for: itemId), let fileUrl = item.fileUrl else { return nil }
        if let data = try? await fileUrlDataController.loadData(for: fileUrl) {
            return data
        }
        guard itemControllable.config.module == .photo,
              let image = await itemControllable.cacheControllable?.photo(for: itemId) else { return nil }
        return image.jpegData(compressionQuality: JPEGQuality.export)
    }

    @MainActor private func token() async -> NetworkModules {
        itemControllable.config.module
    }
}

private extension String {
    /// A version of the string safe to use as a single path component, for filenames
    /// built from user-entered titles (e.g. an adventure name).
    var sanitizedFileNameComponent: String {
        let invalidCharacters: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        let cleaned = String(map { invalidCharacters.contains($0) ? " " : $0 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(80))
    }
}
