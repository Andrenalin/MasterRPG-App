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

/// An `ExportControllable` conformer that resolves `hubControllable` through a
/// shared `ExportModel` box — every module except `AdventureRPG` (which *is*
/// the hub, and returns `root` directly instead). Refining the protocol here
/// rather than adding `exportModel` straight onto `ExportControllable` keeps
/// Adventure's `ExportController` from having to carry an unused property
/// just to satisfy a requirement it doesn't need.
/// Conforming modules only need `let exportModel = ExportModel()` — the
/// getter/preconditionFailure/setter boilerplate every one of them
/// hand-wrote is now this single shared default. See CODE_AUDIT §9.2.
public protocol ExportModelBacked: ExportControllable {
    var exportModel: ExportModel { get }
}

public extension ExportModelBacked {
    var hubControllable: any RootExportControllable {
        get {
            guard let hub = exportModel.hubControllable else {
                preconditionFailure("\(itemControllable.config.module.token) export requires its Adventure export hub after setup.")
            }
            return hub
        }
        set { exportModel.hubControllable = newValue }
    }

    /// Default `exporting(itemIds:)` for "simple" modules (no `diceId`/`photoId`/`mapPins`-style
    /// per-item companion assets to also collect) — forwards straight to
    /// `exportingSimpleEntries(itemIds:)`. Modules that do have companion assets (e.g.
    /// `CharacterRPG`, `MapRPG`) still provide their own `exporting(itemIds:)` override, which
    /// takes precedence over this default via normal witness-table dispatch. Lets a "simple"
    /// module's `ExportController` conform to `ExportModelBacked` with no method body of its
    /// own at all, instead of hand-copying this one-line forward. See CODE_AUDIT §9.2.
    @MainActor func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        exportingSimpleEntries(itemIds: itemIds)
    }
}

public extension ExportControllable {
    // Overwritten in specific
    @MainActor func exportingAll() -> ItemModuleIds {
        ItemModuleIds(dictionary: [itemControllable.config.module: itemControllable.itemDataModel.items.filter { itemControllable.itemSync(for: $0)?.displayState != DisplayStateMask.totalHidden.rawValue }])
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

    /// The id-level BFS traversal shared by every module's `exporting(itemIds:)`:
    /// walk from `seedIds`, log-and-skip an id that no longer resolves, otherwise
    /// keep walking whatever child ids `visit` returns. `visit` receives only the
    /// id — not a typed item — since `itemControllable` here is type-erased and
    /// each module needs its own module-specific fields (`diceId`, `photoId`,
    /// `mapPins`, …), so it looks the item up itself through its own concrete
    /// `itemController` and can also collect cross-module link ids into its own
    /// captured accumulators, exactly as it did inline before this was extracted.
    /// `visit` returns `nil` for "id doesn't resolve" (logged and skipped), or the
    /// (possibly empty) array of same-module child ids to keep walking — dedup
    /// against ids already visited or already queued is handled here, not by
    /// `visit`, so every call site's dedup check could be dropped once extracted.
    @MainActor func bfsExportResults(seedIds: [UUID], visit: (UUID) -> [UUID]?) -> Set<UUID> {
        var checkIds = seedIds
        var results: Set<UUID> = []
        while !checkIds.isEmpty {
            let id = checkIds.removeLast()
            guard let childIds = visit(id) else {
                // Intentionally fire-and-forget: `bfsExportResults` is a synchronous,
                // tight-loop function called from every module's `exporting(itemIds:)`
                // override, and this is purely a diagnostic log line — not worth making
                // the whole BFS (and every override) `async` for. See CODE_AUDIT_EditItem §3.4.
                Task { await self.logExport(title: "exporting not found \(id.uuidString)", count: 1) }
                continue
            }
            results.insert(id)
            for childId in childIds where !(results.contains(childId) || checkIds.contains(childId)) {
                checkIds.append(childId)
            }
        }
        return results
    }

    /// Default `exporting(itemIds:)` body for modules with no per-item
    /// companion assets to pull in beyond their own item tree — walk from the
    /// seed ids through same-module `entries`, treating a leaf item's
    /// `entries` as cross-references rather than containment (`specialCategory`
    /// distinguishes container items — folders/collections — from leaves, so a
    /// leaf's traversal stops there instead of following its cross-links).
    ///
    /// Every "simple" module (no `diceId`/`photoId`/`mapPins`-style fields to
    /// also collect) should implement `exporting(itemIds:)` as exactly
    /// `exportingSimpleEntries(itemIds: itemIds)` rather than hand-copying
    /// this BFS — see CODE_AUDIT §9.4/§5.1 for the drift that duplicating it
    /// already caused once.
    @MainActor func exportingSimpleEntries(itemIds: ItemModuleIds) -> ItemModuleIds {
        let results = bfsExportResults(seedIds: itemIds.ids[itemControllable.config.module, default: []]) { id in
            guard let item = itemControllable.itemSync(for: id) else { return nil }
            guard item.specialCategory else { return [] }
            return item.entries.compactMap { entryId in
                itemControllable.itemSync(for: entryId.childId) != nil ? entryId.childId : nil
            }
        }
        return finalizeExportResults(results, into: itemIds)
    }

    /// The tail every module's `exporting(itemIds:)` shares: promote folders,
    /// stamp the module's own resolved ids, and merge in any partial-folder ids.
    @MainActor func finalizeExportResults(_ results: Set<UUID>, into itemIds: ItemModuleIds) -> ItemModuleIds {
        var results = results
        let partialFolderIds = exportingFolder(results: &results)
        var allIds = itemIds
        allIds.ids[itemControllable.config.module] = Array(results)
        allIds.mergePartial(ids: Array(partialFolderIds), for: itemControllable.config.module)
        return allIds
    }

    func logExport(title: String, count: Int) async {
        // `token()` already exists below for exactly this @MainActor read.
        let module = await token()
        Logger.exportController.info("\(title, privacy: .public) \(module.token, privacy: .public) count: \(count)")
    }

    func logExport(title: String, count: Int, exportModel: ItemDataExportModel) async {
        let module = await token()
        let (exportedItems, totalItems) = await exportProgress(exportModel)
        Logger.exportController.info("\(title, privacy: .public) \(module.token, privacy: .public) currentItems \(count), exportedItems \(exportedItems), total: \(totalItems)")
    }

    @MainActor
    private func exportProgress(_ exportModel: ItemDataExportModel) -> (exportedItems: Int, totalItems: Int) {
        (exportModel.exportedItems, exportModel.totalExportingItems)
    }

    // MARK: - Exporters

    // Save Game / normal export
    @MainActor func createExport(itemIds: ItemModuleIds, into url: URL, exportModel: ItemDataExportModel) -> Task<Void, any Error> {
        let exportController = rootExportController

        return Task.detached(priority: .userInitiated) {
            let securityScope = url.startSecurityScopedAccess()
            defer { securityScope.stop() }
            // Export into a temporary file and replace the destination only once the export is
            // complete: `OutputStream(url:append:false)` truncates immediately, so a
            // failed or cancelled export used to destroy the previous backup at `url`.
            // See CODE_AUDIT_15 §5.7.
            let temporaryUrl = URL.temporaryDirectory.appending(path: "export-\(UUID().uuidString).part")
            guard let outputStream = OutputStream(url: temporaryUrl, append: false) else { throw ItemDataExportableError.openError }

            outputStream.open()
            defer { try? FileManager.default.removeItem(at: temporaryUrl) }

            // `Task.detached` doesn't inherit any ambient actor isolation (unlike a plain
            // `Task { }` literal written inside a @MainActor context elsewhere in this
            // file), so these genuinely need an actor-isolated function call rather than
            // just an `await`-prefixed property access.
            await self.beginExport(exportModel)
            let itemIds = await self.resolveExportIds(itemIds, exportModel: exportModel)

            do {
                try outputStream.append(fileHeader: GmzFileHeader(counter: itemIds.count, token: ExportDataToken.counter.rawValue, version: ExportDataToken.version_2024.rawValue))
                _ = try await exportController.export(itemIds: itemIds, into: outputStream, exportModel: exportModel)
                outputStream.close()
                try Self.replaceExport(at: url, with: temporaryUrl)
                await self.endExport(exportModel)
            } catch {
                outputStream.close()
                await self.endExport(exportModel)
                throw error
            }
        }
    }

    /// Moves a finished export over `destination`. Falls back to copy-over when the destination
    /// cannot be replaced in place (a picked file whose folder is not writable).
    private nonisolated static func replaceExport(at destination: URL, with finished: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            try fileManager.moveItem(at: finished, to: destination)
            return
        }
        do {
            _ = try fileManager.replaceItemAt(destination, withItemAt: finished)
        } catch {
            try Data(contentsOf: finished).write(to: destination, options: .atomic)
        }
    }

    @MainActor
    private func beginExport(_ exportModel: ItemDataExportModel) {
        exportModel.isExportRunning = true
        exportModel.exportedItems = 0
        exportModel.totalExportingItems = 0
    }

    @MainActor
    private func resolveExportIds(_ itemIds: ItemModuleIds, exportModel: ItemDataExportModel) -> ItemModuleIds {
        let ids = exporting(itemIds: itemIds)
        exportModel.totalExportingItems = ids.count
        return ids
    }

    @MainActor
    private func endExport(_ exportModel: ItemDataExportModel) {
        exportModel.isExportRunning = false
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
        // `ItemDataExportModel.init()` is itself `@MainActor` — `await` alone hops there
        // to construct it, no `MainActor.run` wrapper needed (calling an isolated
        // initializer/function works the same as calling an isolated method).
        let exportModel = await ItemDataExportModel()
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
            let data = try await encoded(item)

            if await !exportModel.exportWithoutFileData {
                if let fileData = await inlineFiles(for: itemId) {
                    try outputStream.append(counter: fileData.count, token: ExportDataToken.file.rawValue)
                    try outputStream.write(data: fileData)
                } else if await hasFileData(for: itemId) {
                    // The item has a file, but reading it failed — record it instead of
                    // silently writing a backup that looks complete. See §5.10.
                    await recordMissingFileData(for: itemId, exportModel: exportModel)
                }
            }
            try outputStream.append(counter: data.count, token: ExportDataToken.item.rawValue)
            try outputStream.write(data: data)
            await incrementExportedItems(exportModel)
            await Task.yield()
        }
    }

    @MainActor
    private func encoded<T: Encodable>(_ item: T) throws -> Data {
        try JSONCoding.encoder.encode(item)
    }

    @MainActor
    private func incrementExportedItems(_ exportModel: ItemDataExportModel) {
        exportModel.exportedItems += 1
    }

    @MainActor private func inlineFiles(for itemId: UUID) async -> Data? {
        guard let fileUrlDataController, let item = await itemControllable.item(for: itemId), let fileUrl = item.fileUrl else { return nil }
        // Previously fell back to the cached thumbnail re-encoded as JPEG for photos —
        // that silently changes the exported format (transparency and original bytes
        // lost, hashes differ) while still reporting the export as successful. Report
        // the read failure instead of substituting different bytes. See §5.10.
        return try? await fileUrlDataController.loadData(for: fileUrl)
    }

    @MainActor private func hasFileData(for itemId: UUID) async -> Bool {
        await itemControllable.item(for: itemId)?.fileUrl != nil
    }

    @MainActor private func recordMissingFileData(for itemId: UUID, exportModel: ItemDataExportModel) {
        exportModel.itemsWithMissingFileData.insert(itemId)
        Logger.exportController.error("ExportControllable: failed to read file data for item \(itemId, privacy: .public); exporting without it.")
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
