// @copyright André Trettin

import Foundation
import os.log
import Observation

// MARK: - Import State

public enum ImportMode: Hashable, Sendable, CaseIterable {
    case merge, overwrite, manual
}

/// What a game peer's package may write into this device's library. A peer is only trusted
/// with its own data, so an item is admitted when it is the peer's primary item, was
/// introduced by this same peer before, or does not exist here yet — a package can never
/// overwrite another item the device already owns. The item count is capped as well.
/// See CODE_AUDIT_15 §5.2.
@MainActor
public final class PeerImportPolicy {
    public static let defaultMaximumItems = 256

    public let primaryItemId: UUID
    public let maximumItems: Int
    public private(set) var ownedItemIds: Set<UUID>
    public private(set) var admittedItemIds: Set<UUID> = []
    public private(set) var rejectedItemCount = 0

    public init(primaryItemId: UUID, ownedItemIds: Set<UUID> = [], maximumItems: Int = PeerImportPolicy.defaultMaximumItems) {
        self.primaryItemId = primaryItemId
        self.ownedItemIds = ownedItemIds
        self.maximumItems = maximumItems
    }

    /// Ids the peer has introduced so far, to hand back to the caller for the next package.
    public var introducedItemIds: Set<UUID> { ownedItemIds.union(admittedItemIds) }

    /// INTENDED BEHAVIOR — do not "fix" (CODE_AUDIT_17 §6.1, decided won't fix): the peer's
    /// primary item (its own Character) is admitted even when it already exists locally, so a
    /// player can overwrite that Character on the master to update its values. Reaching this
    /// path needs a connected peer: LAN is PIN-protected, unknown connections are only accepted
    /// if the game master allows them, and SharePlay is a real FaceTime call.
    func admit(itemId: UUID, existsLocally: Bool) -> Bool {
        let isAllowed = itemId == primaryItemId
            || ownedItemIds.contains(itemId)
            || !existsLocally
        guard isAllowed, admittedItemIds.count < maximumItems || admittedItemIds.contains(itemId) else {
            rejectedItemCount += 1
            return false
        }
        admittedItemIds.insert(itemId)
        return true
    }
}

@MainActor @Observable
public final class ItemDataImportModel {
    public init() {}

    /// Lets a caller set the initial mode atomically with construction — calling an
    /// isolated initializer with `await` works the same as calling an isolated method;
    /// only a bare property *write* on an already-existing instance needs its own
    /// isolated function (see CODE_AUDIT §3.2).
    public convenience init(importMode: ImportMode) {
        self.init()
        self.importMode = importMode
    }

    /// Set for data received from a game peer instead of a file the user picked: the sender
    /// controls every field of it, so imported `FileUrl`s get the strictest sanitising.
    /// See CODE_AUDIT_15 §5.1 / §6.3.
    public convenience init(importMode: ImportMode, isUntrustedSource: Bool) {
        self.init(importMode: importMode)
        self.isUntrustedSource = isUntrustedSource
    }

    public private(set) var isUntrustedSource: Bool = false

    /// Limits what a peer's package may write; see `PeerImportPolicy`.
    public private(set) var peerPolicy: PeerImportPolicy?

    public convenience init(importMode: ImportMode, peerPolicy: PeerImportPolicy?) {
        self.init(importMode: importMode, isUntrustedSource: true)
        self.peerPolicy = peerPolicy
    }

    public var importedItems: Int = 0
    /// Items of the import that could not be decoded or applied. Shown after the import so a
    /// partly failed file no longer reads as a clean success. See CODE_AUDIT_15 §5.7.
    public var failedItems: Int = 0
    public var totalImportingItems: Int = 0
    public var isImportRunning: Bool = false
    public var importMode: ImportMode = .merge
    public var isReviewReady: Bool = false
    var reviewModel: ImportReviewModel? = nil

    var pendingModules: [NetworkModules: [ImportReviewItemModel]] = [:]
    var withOverwrite: Bool { importMode == .overwrite }
    var isFinalizingImport: Bool {
        isImportRunning
            && totalImportingItems > 0
            && importedItems >= totalImportingItems
    }

    func finalizeReview() {
        let modules = pendingModules
            .map { ImportReviewModule(id: $0.key, reviewItems: $0.value) }
            .sorted { $0.name < $1.name }
        reviewModel = modules.isEmpty ? nil : ImportReviewModel(modules: modules)
        isReviewReady = true
    }
}

// MARK: - Protocol

public protocol ImportControllable: Sendable {
    var itemControllable: any ItemControllable { get }
    var editControllable: any EditControllable { get }

    func additionalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws
    func finalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws
}

public enum ItemDataImportableError: Error {
    case openError
    case notEnoughData
    case unsupportedDataType
    case fileWithoutItem
    case cancel
}

// MARK: - Import Entry Points

public extension ImportControllable {
    var fileUrlDataController: FileUrlDataController? { itemControllable.fileUrlDataController }

    func additionalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws {}

    func finalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws {}

    // Import from file URL with caller-owned model (progress UI); mode is read from importModel.importMode.
    // `gameMemoryOnly` writes every imported item straight into that module's game memory
    // (`ItemControllable.replaceForGame(policy: .memoryOnly)`), leaving the permanent library and
    // `isGameMode` untouched — used to load a saved game without requiring a game to be running.
    func importUrl(from url: URL, importModel: ItemDataImportModel, gameMemoryOnly: Bool = false) -> Task<Void, any Error> {
        Task.detached(priority: .userInitiated) {
            try await self.performImport(from: url, importModel: importModel, gameMemoryOnly: gameMemoryOnly)
        }
    }

    // Convenience for fire-and-forget callers — no progress UI
    func importUrl(from url: URL, withOverwrite: Bool = false) -> Task<Void, any Error> {
        Task.detached(priority: .userInitiated) {
            let importModel = await ItemDataImportModel(importMode: withOverwrite ? .overwrite : .merge)
            try await self.performImport(from: url, importModel: importModel, gameMemoryOnly: false)
        }
    }

    func importStream(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool = false) async throws {
        guard !Task.isCancelled && inputStream.hasBytesAvailable else { return }

        try await additionalImport(from: inputStream, forceSave: forceSave, importModel: importModel, gameMemoryOnly: gameMemoryOnly)

        let token = await self.token()
        var itemCount = 0
        var version = 0
        while inputStream.hasBytesAvailable {
            guard let moduleHeader = try inputStream.readOptionalHeader() else { break }
            if moduleHeader.token == token {
                itemCount = moduleHeader.counter
                version = moduleHeader.version
                break
            }
            try await skip(itemCount: moduleHeader.counter, from: inputStream, importModel: importModel)
        }
        guard itemCount > 0 else {
            try await finalImport(
                from: inputStream,
                forceSave: forceSave,
                importModel: importModel,
                gameMemoryOnly: gameMemoryOnly
            )
            return
        }

        await logImport(title: "importStream", count: itemCount, importModel: importModel)

        let importsFromUntrustedSource = await importModel.isUntrustedSource
        let peerPolicy = await importModel.peerPolicy
        var currentFile: Data?
        var importedIds: Set<UUID> = []
        var locallyReusedFileIds: Set<UUID> = []
        var deferredFolderItems: [(item: ModelType, id: UUID)] = []

        var counter = 0
        while !Task.isCancelled && counter < itemCount {
            guard inputStream.hasBytesAvailable else { throw ItemDataImportableError.notEnoughData }

            do {
                let (dataSize, dataToken) = try inputStream.readItemHeader()
                let data = try inputStream.readData(size: dataSize)

                switch dataToken {
                case ExportDataToken.file.rawValue:
                    currentFile = data
                case ExportDataToken.item.rawValue:
                    counter += 1
                    // A file token belongs to the item that immediately follows it —
                    // consume it here so a later file-less item cannot inherit it.
                    let itemFile = currentFile
                    currentFile = nil
                    do {
                        // decode constructs models, which may be @MainActor — `decode` is
                        // itself `@MainActor`, so `await` alone hops for the decode call
                        // (no `MainActor.run` wrapper needed); the wire format is unchanged.
                        let itemVersion = version
                        let newItem = try await itemControllable.decode(data: data, with: JSONDecoder(), version: itemVersion)
                        guard await prepareDecodedItem(newItem, allowsPrivateRemoteHosts: !importsFromUntrustedSource, peerPolicy: peerPolicy) else {
                            continue
                        }
                        if let itemFile {
                            if try await addFile(data: itemFile, to: newItem, forceSave: forceSave) {
                                locallyReusedFileIds.insert(newItem.id)
                            }
                        }
                        if await itemControllable.shouldDeferGameModeFolderImport(newItem, forceSave: forceSave) {
                            deferredFolderItems.append((newItem, newItem.id))
                        } else {
                            try await addItem(importedItem: newItem, id: newItem.id, forceSave: forceSave, importModel: importModel, gameMemoryOnly: gameMemoryOnly, locallyReusedFileIds: locallyReusedFileIds)
                        }
                        importedIds.insert(newItem.id)
                    } catch {
                        // A single undecodable item is skipped (and reported); cancelling stops the import.
                        if error is CancellationError { throw error }
                        await recordFailedItem(importModel)
                        await logImport(title: "Error: \(error.localizedDescription)", count: 0, importModel: importModel)
                    }
                    break
                default:
                    throw ItemDataImportableError.unsupportedDataType
                }
            } catch {
                // Framing errors (a truncated block, an unknown token) mean the rest of the
                // stream cannot be trusted, so they fail the import instead of being logged
                // while the import reports success. See CODE_AUDIT_15 §5.7.
                await logImport(title: "Error: \(error.localizedDescription)", count: 0, importModel: importModel)
                throw error
            }
        }

        guard !Task.isCancelled else { return }
        for deferredFolderItem in deferredFolderItems {
            do {
                try await addItem(
                    importedItem: deferredFolderItem.item,
                    id: deferredFolderItem.id,
                    forceSave: forceSave,
                    importModel: importModel,
                    gameMemoryOnly: gameMemoryOnly,
                    locallyReusedFileIds: locallyReusedFileIds
                )
            } catch {
                await logImport(title: "Error: \(error.localizedDescription)", count: 0, importModel: importModel)
            }
        }

        let mode = await importModel.importMode
        if mode == .manual {
            // Collect local items absent from the import stream as deletion candidates
            if itemCount > 0 {
                let module = itemControllable.config.module
                let ic = itemControllable
                let allLocalIds = await localItemIds(of: ic)
                for deletedId in allLocalIds.subtracting(importedIds) {
                    await appendDeletionReviewItem(deletedId: deletedId, module: module, itemController: ic, importModel: importModel)
                }
            }
        } else if !gameMemoryOnly {
            let cc = ConvertController(itemController: itemControllable, editController: editControllable)
            await cc.repairImportedItems(reportModel: ValidateRepairModel(), importedIds: importedIds)
        }

        try await finalImport(
            from: inputStream,
            forceSave: forceSave,
            importModel: importModel,
            gameMemoryOnly: gameMemoryOnly
        )
    }

    // Convenience for game networking imports — no progress tracking needed
    func importStream(from inputStream: InputStream, forceSave: Bool) async throws {
        // `ItemDataImportModel.init()` is itself `@MainActor` — `await` alone hops
        // there, no `MainActor.run` wrapper needed.
        let importModel = await ItemDataImportModel()
        try await importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
    }

    // MARK: - Import Lifecycle

    func logImport(title: String, count: Int, importModel: ItemDataImportModel) async {
        let token = await self.token()
        let (importedItems, totalItems) = await importProgress(importModel)
        Logger.importController.info("\(title, privacy: .public) \(token, privacy: .public) currentItems \(count), importedItems \(importedItems), total: \(totalItems)")
    }

    @MainActor
    private func importProgress(_ importModel: ItemDataImportModel) -> (importedItems: Int, totalItems: Int) {
        (importModel.importedItems, importModel.totalImportingItems)
    }

    @MainActor
    private func localItemIds(of itemController: any ItemControllable) -> Set<UUID> {
        Set(itemController.itemDataModel.items)
    }

    @MainActor
    private func appendDeletionReviewItem(
        deletedId: UUID,
        module: NetworkModules,
        itemController: any ItemControllable,
        importModel: ItemDataImportModel
    ) {
        guard let deletedIA: any ItemDataAccessable = itemController.itemSync(for: deletedId) else { return }
        let reviewItem = SingleReviewItem(existing: deletedIA, imported: deletedIA, merged: deletedIA)
        let itemModel = SingleItemImportModel.from(item: reviewItem)
        let reviewItemModel = ImportReviewItemModel(
            id: deletedId,
            kind: .different,
            existingStatus: deletedIA.name,
            importedStatus: "Not in import",
            mergedStatus: deletedIA.name,
            itemModel: itemModel,
            isDeletion: true
        )
        importModel.pendingModules[module, default: []].append(reviewItemModel)
    }
}

private extension ImportControllable {
    @MainActor
    func token() async -> Int {
        itemControllable.config.module.rawValue
    }

    func performImport(from url: URL, importModel: ItemDataImportModel, gameMemoryOnly: Bool) async throws {
        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        guard let inputStream = InputStream(url: url) else { throw ItemDataImportableError.openError }

        inputStream.open()
        defer { inputStream.close() }

        let fileHeader = try inputStream.readHeader()
        guard fileHeader.token == ExportDataToken.counter.rawValue &&
                fileHeader.version == ExportDataToken.version_2024.rawValue else { throw ItemDataImportableError.notEnoughData }

        await beginImport(importModel, totalItems: fileHeader.counter)

        do {
            try await self.importStream(from: inputStream, forceSave: true, importModel: importModel, gameMemoryOnly: gameMemoryOnly)
            await finishImport(importModel)
        } catch {
            await stopImport(importModel)
            throw Task.isCancelled ? ItemDataImportableError.cancel : error
        }
    }

    @MainActor
    private func beginImport(_ importModel: ItemDataImportModel, totalItems: Int) {
        importModel.importedItems = 0
        importModel.failedItems = 0
        importModel.totalImportingItems = totalItems
        importModel.isImportRunning = true
    }

    @MainActor
    private func finishImport(_ importModel: ItemDataImportModel) {
        importModel.isImportRunning = false
        if importModel.importMode == .manual { importModel.finalizeReview() }
    }

    @MainActor
    private func stopImport(_ importModel: ItemDataImportModel) {
        importModel.isImportRunning = false
    }

    @MainActor
    private func recordFailedItem(_ importModel: ItemDataImportModel) {
        importModel.failedItems += 1
    }

    @MainActor
    private func incrementImportedItems(_ importModel: ItemDataImportModel) {
        importModel.importedItems += 1
    }

    // MARK: - Item Application

    /// Makes a freshly decoded item safe to apply: its file description came out of the imported
    /// bytes and is never resolved as-is (CODE_AUDIT_15 §5.1), and a peer's package may only
    /// write what its `PeerImportPolicy` admits (§5.2). Returns `false` when the item must be
    /// skipped.
    @MainActor
    private func prepareDecodedItem(_ item: any ItemDataAccessable, allowsPrivateRemoteHosts: Bool, peerPolicy: PeerImportPolicy?) -> Bool {
        var item = item
        if let importedFileUrl = item.fileUrl {
            item.fileUrl = importedFileUrl.sanitizedForImport(allowsPrivateRemoteHosts: allowsPrivateRemoteHosts)
        }
        guard let peerPolicy else { return true }
        let existsLocally = itemControllable.itemSync(for: item.id, noGame: true) != nil
        guard peerPolicy.admit(itemId: item.id, existsLocally: existsLocally) else {
            Logger.importController.warning("Import skipped a peer item that is not the sender's own module=\(itemControllable.config.module.rawValue, privacy: .public) item=\(item.id, privacy: .public)")
            return false
        }
        return true
    }

    func addItem(importedItem: ModelType, id: UUID, forceSave: Bool, importModel: ItemDataImportModel, gameMemoryOnly: Bool = false, locallyReusedFileIds: Set<UUID> = []) async throws {
        let mode = await importModel.importMode
        let itemController = itemControllable
        let editCtrl = editControllable
        let normalizedImportedItem = await itemController.normalizedImportedItem(from: importedItem)
        guard let importableItem = await itemController.gameModeImportedItem(from: normalizedImportedItem, forceSave: forceSave, locallyReusedFileIds: locallyReusedFileIds) else {
            await incrementImportedItems(importModel)
            try Task.checkCancellation()
            return
        }

        // A saved-game load never touches the permanent library — write straight into this
        // module's game memory regardless of merge/overwrite mode or isGameMode.
        // `replaceForGame(policy: .memoryOnly)` only fills the game-shadow dictionary
        // (`gameItemData`); nothing considers the item "in the running game" — `gameItems`
        // stays the authority for that (see `ItemGameModel.currentItemId`/`.items`) — until it's
        // in that id list too, so add it there ourselves.
        guard !gameMemoryOnly else {
            await replaceForGameAndCount(importableItem, id: id, itemController: itemController, importModel: importModel)
            try Task.checkCancellation()
            return
        }

        switch mode {
        case .merge:
            let finalItem = await itemController.merge(with: importableItem, forceMerge: forceSave)
            if let finalItem {
                await itemController.replaceImportedModel(model: finalItem, isInsert: true, forceSave: forceSave)
                await editCtrl.repairFolder(itemId: id)
            }

        case .overwrite:
            await itemController.replaceImportedModel(model: importableItem, isInsert: true, forceSave: forceSave)
            await editCtrl.repairFolder(itemId: id)

        case .manual:
            let merged = await itemController.merge(with: importableItem) as? any ItemDataAccessable
            await recordManualReview(importableItem: importableItem, merged: merged, id: id, itemController: itemController, importModel: importModel)
        }

        await incrementImportedItems(importModel)
        try Task.checkCancellation()
    }

    @MainActor
    private func replaceForGameAndCount(
        _ importableItem: ModelType,
        id: UUID,
        itemController: any ItemControllable,
        importModel: ItemDataImportModel
    ) {
        itemController.replaceForGame(model: importableItem, isInsert: true, policy: .memoryOnly)
        if !itemController.itemDataModel.gameItems.contains(id) {
            itemController.itemDataModel.gameItems.insert(id, at: 0)
        }
        importModel.importedItems += 1
    }

    @MainActor
    private func recordManualReview(
        importableItem: ModelType,
        merged: (any ItemDataAccessable)?,
        id: UUID,
        itemController: any ItemControllable,
        importModel: ItemDataImportModel
    ) {
        guard let imported = importableItem as? any ItemDataAccessable else { return }
        let existing = itemController.itemSync(for: id)
        let module = itemController.config.module

        if existing != nil && merged == nil {
            logManualReviewUnchangedSkipped(module: module, id: id, imported: imported)
            return
        }

        let kind: ImportReviewItemModel.ChangeKind = existing == nil ? .added : .different
        let reviewItem = SingleReviewItem(existing: existing, imported: imported, merged: merged ?? imported)
        let itemModel = SingleItemImportModel.from(item: reviewItem)
        if kind == .different {
            logManualReviewDifference(
                module: module,
                id: id,
                existing: existing,
                imported: imported,
                itemModel: itemModel
            )
        }
        let reviewItemModel = ImportReviewItemModel(
            id: id,
            kind: kind,
            existingStatus: existing?.name ?? "Not in library",
            importedStatus: imported.name,
            mergedStatus: kind == .different ? "Merged" : "Ready to add",
            itemModel: itemModel
        )
        importModel.pendingModules[module, default: []].append(reviewItemModel)
    }

    // MARK: - Manual Review Diffing

    @MainActor
    func logManualReviewDifference(
        module: NetworkModules,
        id: UUID,
        existing: (any ItemDataAccessable)?,
        imported: any ItemDataAccessable,
        itemModel: SingleItemImportModel
    ) {
        guard let existing else {
            Logger.importController.info("Manual import review added \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)'")
            return
        }

        let reviewDifferences = reviewPropertyDifferences(in: itemModel) + reviewEntryDifferences(in: itemModel)
        let commonDifferences = commonItemDifferences(existing: existing, imported: imported)
        let reviewSummary = reviewDifferences.importLogSummary
        let commonSummary = commonDifferences.importLogSummary

        if reviewDifferences.isEmpty && commonDifferences.isEmpty {
            Logger.importController.warning("Manual import review different \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)' but review/common fields match. model.isSame returned false; likely CRDT update metadata or module-specific fields not exposed in reviewProperties.")
        } else {
            // User-authored sheet content — imported item/entry field values — defaults to
            // `.private` here (unlike the enum/identifier fields alongside it), matching the
            // project's logging privacy convention. This is the highest-content-volume site of
            // that gap: unredacted excerpts of imported character sheets, adventure notes, or
            // campaign content previously persisted in plaintext system logs during ordinary
            // (non-DEBUG-gated) import review. See CODE_AUDIT §6.4.
            Logger.importController.info("Manual import review different \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)' reviewRows=\(reviewSummary, privacy: .private) commonFields=\(commonSummary, privacy: .private)")
        }
    }

    @MainActor
    func logManualReviewUnchangedSkipped(module: NetworkModules, id: UUID, imported: any ItemDataAccessable) {
        Logger.importController.info("Manual import review unchanged skipped \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)' because merge returned nil (model.isSame == true).")
    }

    @MainActor
    func reviewPropertyDifferences(in itemModel: SingleItemImportModel) -> [String] {
        itemModel.properties.compactMap { property in
            guard itemModel.isChanged(prop: property) else { return nil }
            return "property '\(property.displayName)': existing='\((itemModel.existingValue(for: property) ?? "nil").importLogPreview)' imported='\((itemModel.importedValue(for: property) ?? "nil").importLogPreview)' merged='\((itemModel.mergedValue(for: property) ?? "nil").importLogPreview)'"
        }
    }

    @MainActor
    func reviewEntryDifferences(in itemModel: SingleItemImportModel) -> [String] {
        itemModel.entries.flatMap { entryModel in
            let entryLabel = "\(entryModel.name.importLogPreview) (\(entryModel.id.uuidString))"

            if entryModel.entry.existing == nil {
                return ["entry added '\(entryLabel)'"]
            }
            if entryModel.entry.imported == nil {
                return ["entry missing from import '\(entryLabel)'"]
            }

            return entryModel.properties.compactMap { property in
                guard entryModel.isChanged(prop: property) else { return nil }
                return "entry '\(entryLabel)' property '\(property.displayName)': existing='\((entryModel.existingValue(for: property) ?? "nil").importLogPreview)' imported='\((entryModel.importedValue(for: property) ?? "nil").importLogPreview)' merged='\((entryModel.mergedValue(for: property) ?? "nil").importLogPreview)'"
            }
        }
    }

    @MainActor
    func commonItemDifferences(existing: any ItemDataAccessable, imported: any ItemDataAccessable) -> [String] {
        var differences: [String] = []

        appendImportDifference("id", existing.id.uuidString, imported.id.uuidString, to: &differences)
        appendImportDifference("name", existing.name, imported.name, to: &differences)
        appendImportDifference("description", existing.description, imported.description, to: &differences)
        appendImportDifference("tags", existing.tags.joined(separator: ","), imported.tags.joined(separator: ","), to: &differences)
        appendImportDifference("category", "\(existing.category.rawValue)", "\(imported.category.rawValue)", to: &differences)
        appendImportDifference("displayState", "\(existing.displayState)", "\(imported.displayState)", to: &differences)
        appendImportDifference("isGroupHiddenToggle", "\(existing.isGroupHiddenToggle)", "\(imported.isGroupHiddenToggle)", to: &differences)
        appendImportDifference("parentId", existing.parentId?.uuidString ?? "nil", imported.parentId?.uuidString ?? "nil", to: &differences)
        differences += fileDifferences(existing: existing.fileUrl, imported: imported.fileUrl)
        differences += entryDifferences(existing: existing.entries, imported: imported.entries)

        return differences
    }

    func fileDifferences(existing: FileUrl?, imported: FileUrl?) -> [String] {
        var differences: [String] = []
        appendImportDifference("file.id", existing?.fileId.uuidString ?? "nil", imported?.fileId.uuidString ?? "nil", to: &differences)
        appendImportDifference("file.url", existing?.rawUrl.absoluteString ?? "nil", imported?.rawUrl.absoluteString ?? "nil", to: &differences)
        appendImportDifference("file.location", existing.map { "\($0.location)" } ?? "nil", imported.map { "\($0.location)" } ?? "nil", to: &differences)
        appendImportDifference("file.module", existing?.module ?? "nil", imported?.module ?? "nil", to: &differences)
        appendImportDifference("file.contentHash", existing?.contentHash ?? "nil", imported?.contentHash ?? "nil", to: &differences)
        return differences
    }

    func entryDifferences(existing: [any EntryDataAccessable], imported: [any EntryDataAccessable]) -> [String] {
        var differences: [String] = []
        let existingIds = existing.map(\.id)
        let importedIds = imported.map(\.id)
        appendImportDifference("entry.ids", existingIds.map(\.uuidString).joined(separator: ","), importedIds.map(\.uuidString).joined(separator: ","), to: &differences)

        let allIds = (existingIds + importedIds).reduce(into: [UUID]()) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }

        for id in allIds {
            let existingEntry = existing.first { $0.id == id }
            let importedEntry = imported.first { $0.id == id }
            let entryPrefix = "entry \(id.uuidString)"

            guard let existingEntry, let importedEntry else {
                appendImportDifference("\(entryPrefix).presence", existingEntry == nil ? "missing" : "present", importedEntry == nil ? "missing" : "present", to: &differences)
                continue
            }

            appendImportDifference("\(entryPrefix).childId", existingEntry.childId.uuidString, importedEntry.childId.uuidString, to: &differences)
            appendImportDifference("\(entryPrefix).name", existingEntry.name, importedEntry.name, to: &differences)
            appendImportDifference("\(entryPrefix).content", existingEntry.content, importedEntry.content, to: &differences)
            appendImportDifference("\(entryPrefix).displayState", "\(existingEntry.displayState)", "\(importedEntry.displayState)", to: &differences)
        }

        return differences
    }

    func appendImportDifference(_ label: String, _ existing: String, _ imported: String, to differences: inout [String]) {
        guard existing != imported else { return }
        differences.append("\(label): existing='\(existing.importLogPreview)' imported='\(imported.importLogPreview)'")
    }

    // MARK: - File Handling

    func skip(itemCount: Int, from inputStream: InputStream, importModel: ItemDataImportModel) async throws {
        await logImport(title: "skip", count: itemCount, importModel: importModel)
        var counter = 0
        while counter < itemCount {
            guard inputStream.hasBytesAvailable else {
                throw ItemDataImportableError.notEnoughData
            }

            let (dataSize, dataToken) = try inputStream.readItemHeader()
            let _ = try inputStream.readData(size: dataSize)
            if dataToken == ExportDataToken.item.rawValue {
                counter += 1
            }
        }
    }

    @MainActor func addFile(data: Data, to item: any ItemDataAccessable, forceSave: Bool) async throws -> Bool {
        guard let fileUrlDataController, var fileUrl = item.fileUrl else { return false }
        var item = item
        let module = itemControllable.config.module.rawValue
        let importedHash = FileUrl.contentHash(of: data)
        let localFileUrl = itemControllable.itemSync(for: item.id, noGame: true)?.fileUrl

        // Reuse the existing file when the binary is unchanged — do not write the same file again
        if let existingFileUrl = await reusableExistingFileUrl(for: item.id, importedHash: importedHash, forceSave: forceSave) {
            Logger.importController.debug("Import addFile reuses existing file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(existingFileUrl.fileId, privacy: .public) hash=\(importedHash, privacy: .public) forceSave=\(forceSave, privacy: .public)")
            item.fileUrl = existingFileUrl
            if forceSave == false, let localItem = itemControllable.itemSync(for: item.id, noGame: true) {
                item.parentId = localItem.parentId
            }
            return forceSave == false
        }

        if let localFileUrl {
            Logger.importController.warning("Import addFile rewrites existing file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(fileUrl.fileId, privacy: .public) forceSave=\(forceSave, privacy: .public) localHash=\(localFileUrl.contentHash ?? "nil", privacy: .public) importedHash=\(importedHash, privacy: .public) localUrl=\(localFileUrl.rawUrl.absoluteString, privacy: .private) importedUrl=\(fileUrl.rawUrl.absoluteString, privacy: .private)")
        } else {
            Logger.importController.debug("Import addFile writes new file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(fileUrl.fileId, privacy: .public) hash=\(importedHash, privacy: .public) forceSave=\(forceSave, privacy: .public)")
        }

        fileUrl.resetData(data)
        do {
            let updated = try await fileUrlDataController.createNewFileUrl(fileId: fileUrl.fileId, unconvertedFileUrl: fileUrl, pathExtension: fileUrl.rawUrl.pathExtension)
            Logger.importController.debug("Import addFile stored imported file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(fileUrl.fileId, privacy: .public) storedUrl=\((updated ?? fileUrl).rawUrl.absoluteString, privacy: .private) storedHash=\((updated ?? fileUrl).contentHash ?? "nil", privacy: .public)")
            await itemControllable.reset(fileUrl: updated ?? fileUrl, item: &item)
        } catch {
            Logger.importController.error("Cannot save bookmark \(module, privacy: .public), file stored as data")
            await itemControllable.reset(fileUrl: fileUrl, item: &item)
        }
        return false
    }

    /// The existing item's local file URL when the imported bytes are unchanged.
    /// In game mode (`forceSave == false`) this deliberately avoids writing a
    /// content-hash-only change back into the game item observed by the UI.
    @MainActor func reusableExistingFileUrl(for itemId: UUID, importedHash: String, forceSave: Bool) async -> FileUrl? {
        guard let existing = itemControllable.itemSync(for: itemId, noGame: true), var existingFileUrl = existing.fileUrl else { return nil }
        if let contentHash = existingFileUrl.contentHash {
            guard contentHash == importedHash else { return nil }
            // A matching hash is not enough: a metadata-only import carries the
            // hash without the binary. Only reuse when the file really exists.
            guard await fileUrlDataController?.hasLocalData(for: existingFileUrl) == true else { return nil }
            return existingFileUrl
        }
        guard let data = try? await fileUrlDataController?.loadData(for: existingFileUrl) else { return nil }
        guard FileUrl.contentHash(of: data) == importedHash else { return nil }
        guard forceSave else { return existingFileUrl }

        existingFileUrl.resetContentHash(of: data)
        persist(fileUrl: existingFileUrl, itemId: itemId)
        return existingFileUrl
    }

    @MainActor
    func persist(fileUrl: FileUrl, itemId: UUID) {
        guard var copy = itemControllable.itemSync(for: itemId, noGame: true)?.copy() else { return }
        copy.fileUrl = fileUrl
        itemControllable.replace(model: copy, isInsert: false, forceSave: true)
    }
}

private extension ItemControllable {
    @MainActor
    func shouldDeferGameModeFolderImport(_ item: ModelType, forceSave: Bool) -> Bool {
        guard forceSave == false, itemDataModel.isGameMode, let imported = item as? Model else { return false }
        return imported.category == .folder
    }

    @MainActor
    func normalizedImportedItem(from item: ModelType) -> ModelType {
        guard var imported = (item as? Model)?.copy() else { return item }
        normalizeImportedItemForMerge(in: &imported)
        return imported
    }

    @MainActor
    func gameModeImportedItem(from item: ModelType, forceSave: Bool, locallyReusedFileIds: Set<UUID>) -> ModelType? {
        guard forceSave == false, itemDataModel.isGameMode, var imported = (item as? Model)?.copy() else { return item }

        if locallyReusedFileIds.contains(imported.id), let localItem = itemSync(for: imported.id, noGame: true) {
            imported.parentId = localItem.parentId
            return imported
        }

        guard imported.category == .folder, !locallyReusedFileIds.isEmpty else { return imported }
        imported.entries.removeAll { locallyReusedFileIds.contains($0.childId) }
        return imported.entries.isEmpty ? nil : imported
    }

    @MainActor
    func normalizeImportedItemForMerge(in item: inout Model) {
        ImportItemRepair.normalizeLegacyCategory(in: &item)

        if config.module == .photo && item.category == .entry {
            item.entries = []
        }
    }
}

private extension Array where Element == String {
    var importLogSummary: String {
        guard !isEmpty else { return "none" }
        let maxItems = 16
        let visibleItems = prefix(maxItems)
        let summary = visibleItems.joined(separator: " | ")
        let remainingCount = count - visibleItems.count
        guard remainingCount > 0 else { return summary }
        return "\(summary) | +\(remainingCount) more"
    }
}

private extension String {
    var importLogPreview: String {
        let maxLength = 240
        let flattened = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing("\n", with: "\\n")
            .replacing("\r", with: "\\r")
        guard flattened.count > maxLength else { return flattened }
        return "\(String(flattened.prefix(maxLength)))..."
    }
}

// MARK: - Binary Stream Reading

extension InputStream {
    func readHeader() throws -> GmzFileHeader {
        GmzFileHeader(counter: try readCounter(), token: try readCounter(), version: try readCounter())
    }

    /// Reads the next module header while treating a clean stream boundary as normal EOF.
    /// File-backed input streams can report `hasBytesAvailable == true` until one final read,
    /// so scanning optional trailing modules cannot use that property alone.
    func readOptionalHeader() throws -> GmzFileHeader? {
        var readBuffer = [UInt8](repeating: 0, count: 4)
        let readCount = read(&readBuffer, maxLength: readBuffer.count)
        guard readCount != 0 else { return nil }
        guard readCount == readBuffer.count else {
            throw ItemDataImportableError.notEnoughData
        }

        let counter = readBuffer.reversed().reduce(UInt32(0)) { result, byte in
            result << 8 | UInt32(byte)
        }
        return GmzFileHeader(
            counter: Int(counter),
            token: try readCounter(),
            version: try readCounter()
        )
    }

    func readItemHeader() throws -> (Int, Int) {
        (try readCounter(), try readCounter())
    }

    func readCounter() throws -> Int {
        var readBuffer = [UInt8](repeating: 0, count: 4)
        let readCount = read(&readBuffer, maxLength: readBuffer.count)
        guard readCount == readBuffer.count else {
            throw ItemDataImportableError.notEnoughData
        }

        let u32 = readBuffer.reversed().reduce(0) { soFar, byte in
            return soFar << 8 | UInt32(byte)
        }
        return Int(u32)
    }

    /// Upper bound on a single item/file block's declared size. `size` below comes
    /// straight off the wire (a 4-byte counter, up to ~4.29 billion) with nothing else
    /// validating it first — without this cap a single corrupted or malicious header
    /// (from a bad import file, or a peer's SharePlay/Bonjour network payload) would
    /// make `readData(size:)` attempt a multi-gigabyte allocation before the
    /// subsequent `read` call ever gets a chance to fail with `.notEnoughData`. See
    /// CODE_AUDIT_Import §6.1. 512 MB comfortably covers the largest legitimate single
    /// blob this format carries (an embedded PDF or 3D object file) with headroom.
    static let maxSingleBlockSize = 512 * 1_024 * 1_024

    func readData(size: Int) throws -> Data {
        guard size >= 0, size <= Self.maxSingleBlockSize else {
            throw ItemDataImportableError.notEnoughData
        }
        // Read in bounded chunks instead of allocating `size` bytes up front: a truncated
        // file with a large declared size used to allocate (and zero) up to 512 MB before
        // the first read could fail, and a partial read was treated as a failure.
        // See CODE_AUDIT_15 §5.7.
        var data = Data()
        data.reserveCapacity(min(size, Self.readChunkSize))
        var chunk = [UInt8](repeating: 0, count: min(size, Self.readChunkSize))
        while data.count < size {
            let wanted = min(chunk.count, size - data.count)
            let readCount = read(&chunk, maxLength: wanted)
            guard readCount > 0 else {
                throw ItemDataImportableError.notEnoughData
            }
            data.append(chunk, count: readCount)
        }
        return data
    }

    private static let readChunkSize = 1_024 * 1_024
}
