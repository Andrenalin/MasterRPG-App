// @copyright André Trettin

import Foundation
import os.log
import Observation

public enum ImportMode: Hashable, Sendable, CaseIterable {
    case merge, overwrite, manual
}

public enum ImportResolution: Hashable, Sendable, CaseIterable {
    case old, new, merge
}

public struct ImportReviewItem: Identifiable, Sendable {
    public enum Kind: Sendable { case new, updated, deleted }

    public let id: UUID
    public let name: String
    public let moduleName: String
    public let kind: Kind
    public var resolution: ImportResolution
    let applyResolution: @MainActor @Sendable (ImportResolution) async -> Void
}

@MainActor @Observable
public final class ItemDataImportModel {
    public init() {}

    public var importedItems: Int = 0
    public var totalImportingItems: Int = 0
    public var isImportRunning: Bool = false
    public var importMode: ImportMode = .merge
    public var reviewItems: [ImportReviewItem] = []
    public var isReviewReady: Bool = false

    var withOverwrite: Bool { importMode == .overwrite }
}

public protocol ImportControllable: Sendable {
    var itemControllable: any ItemControllable { get }
    var editControllable: any EditControllable { get }

    func additionalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel) async throws
}

public enum ItemDataImportableError: Error {
    case openError
    case notEnoughData
    case unsupportedDataType
    case fileWithoutItem
    case cancel
}

public extension ImportControllable {
    var fileUrlDataController: FileUrlDataController? { itemControllable.fileUrlDataController }

    func additionalImport(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel) async throws {}

    // Import from file URL with caller-owned model (progress UI); mode is read from importModel.importMode
    func importUrl(from url: URL, importModel: ItemDataImportModel) -> Task<Void, any Error> {
        Task.detached(priority: .userInitiated) {
            try await self.performImport(from: url, importModel: importModel)
        }
    }

    // Convenience for fire-and-forget callers — no progress UI
    func importUrl(from url: URL, withOverwrite: Bool = false) -> Task<Void, any Error> {
        Task.detached(priority: .userInitiated) {
            let importModel = await MainActor.run { ItemDataImportModel() }
            await MainActor.run { importModel.importMode = withOverwrite ? .overwrite : .merge }
            try await self.performImport(from: url, importModel: importModel)
        }
    }

    func importStream(from inputStream: InputStream, forceSave: Bool, importModel: ItemDataImportModel) async throws {
        guard !Task.isCancelled && inputStream.hasBytesAvailable else { return }

        try await additionalImport(from: inputStream, forceSave: forceSave, importModel: importModel)

        let token = await self.token()
        var itemCount = 0
        var version = 0
        while inputStream.hasBytesAvailable {
            let moduleHeader = try inputStream.readHeader()
            if moduleHeader.token == token {
                itemCount = moduleHeader.counter
                version = moduleHeader.version
                break
            }
            try await skip(itemCount: moduleHeader.counter, from: inputStream, importModel: importModel)
        }
        guard itemCount > 0 else { return }

        await logImport(title: "importStream", count: itemCount, importModel: importModel)

        let decoder = JSONDecoder()
        var currentFile: Data?
        var importedIds: Set<UUID> = []

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
                    do {
                        let newItem = try itemControllable.decode(data: data, with: decoder, version: version)
                        if let currentFile {
                            try await addFile(data: currentFile, to: newItem)
                        }
                        try await addItem(importedItem: newItem, id: newItem.id, forceSave: forceSave, importModel: importModel)
                        importedIds.insert(newItem.id)
                    } catch {
                        await logImport(title: "Error: \(error.localizedDescription)", count: 0, importModel: importModel)
                    }
                    break
                default:
                    throw ItemDataImportableError.unsupportedDataType
                }
            } catch {
                await logImport(title: "Error: \(error.localizedDescription)", count: 0, importModel: importModel)
            }
        }

        guard !Task.isCancelled else { return }
        let mode = await importModel.importMode
        if mode == .manual {
            // Collect local items absent from the import stream as deletion candidates
            if itemCount > 0 {
                let module = itemControllable.config.module
                let ic = itemControllable
                let allLocalIds = await MainActor.run { Set(ic.itemDataModel.items) }
                for deletedId in allLocalIds.subtracting(importedIds) {
                    let itemName = await MainActor.run { ic.nameSync(itemId: deletedId) }
                    let reviewItem = ImportReviewItem(
                        id: deletedId,
                        name: itemName,
                        moduleName: module.title,
                        kind: .deleted,
                        resolution: .old,
                        applyResolution: { resolution in
                            if resolution == .new { await ic.delete(itemId: deletedId) }
                        }
                    )
                    await MainActor.run { importModel.reviewItems.append(reviewItem) }
                }
            }
        } else {
            let cc = ConvertController(itemController: itemControllable, editController: editControllable)
            await cc.repairHiddenAndFolders(reportModel: ValidateRepairModel(), importedIds: importedIds)
        }
    }

    // Convenience for game networking imports — no progress tracking needed
    func importStream(from inputStream: InputStream, forceSave: Bool) async throws {
        let importModel = await MainActor.run { ItemDataImportModel() }
        try await importStream(from: inputStream, forceSave: forceSave, importModel: importModel)
    }

    func logImport(title: String, count: Int, importModel: ItemDataImportModel) async {
        let (token, importedItems, totalItems) = await MainActor.run {
            (itemControllable.config.module.rawValue, importModel.importedItems, importModel.totalImportingItems)
        }
        Logger.importController.info("\(title, privacy: .public) \(token, privacy: .public) currentItems \(count), importedItems \(importedItems), total: \(totalItems)")
    }
}

private extension ImportControllable {
    @MainActor
    func token() async -> Int {
        itemControllable.config.module.rawValue
    }

    func performImport(from url: URL, importModel: ItemDataImportModel) async throws {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        guard let inputStream = InputStream(url: url) else { throw ItemDataImportableError.openError }

        inputStream.open()
        defer { inputStream.close() }

        let fileHeader = try inputStream.readHeader()
        guard fileHeader.token == ExportDataToken.counter.rawValue && fileHeader.version == ExportDataToken.version_2024.rawValue else { throw ItemDataImportableError.notEnoughData }

        await MainActor.run {
            importModel.importedItems = 0
            importModel.totalImportingItems = fileHeader.counter
            importModel.isImportRunning = true
        }

        do {
            try await self.importStream(from: inputStream, forceSave: true, importModel: importModel)
            await MainActor.run {
                importModel.isImportRunning = false
                if importModel.importMode == .manual { importModel.isReviewReady = true }
            }
        } catch {
            await MainActor.run { importModel.isImportRunning = false }
            throw Task.isCancelled ? ItemDataImportableError.cancel : error
        }
    }

    func addItem(importedItem: ModelType, id: UUID, forceSave: Bool, importModel: ItemDataImportModel) async throws {
        let mode = await importModel.importMode
        let itemController = itemControllable
        let editCtrl = editControllable

        switch mode {
        case .merge:
            let finalItem = await itemController.merge(with: importedItem, forceMerge: forceSave)
            if let finalItem {
                await itemController.replace(model: finalItem, isInsert: true, forceSave: forceSave)
                await editCtrl.repairFolder(itemId: id)
            }

        case .overwrite:
            await itemController.replace(model: importedItem, isInsert: true, forceSave: forceSave)
            await editCtrl.repairFolder(itemId: id)

        case .manual:
            let existsLocally = await MainActor.run { itemController.itemSync(for: id) != nil }
            let kind: ImportReviewItem.Kind = existsLocally ? .updated : .new
            let mergedItem: ModelType? = existsLocally ? await itemController.merge(with: importedItem) : importedItem
            let itemName = (importedItem as? any ItemDataAccessable)?.name ?? id.uuidString
            let moduleName = itemController.config.module.title
            let reviewItem = ImportReviewItem(
                id: id,
                name: itemName,
                moduleName: moduleName,
                kind: kind,
                resolution: kind == .new ? .new : .merge,
                applyResolution: { resolution in
                    switch resolution {
                    case .old: break
                    case .new:
                        await itemController.replace(model: importedItem, isInsert: true, forceSave: true)
                        await editCtrl.repairFolder(itemId: id)
                    case .merge:
                        if let merged = mergedItem {
                            await itemController.replace(model: merged, isInsert: true, forceSave: true)
                            await editCtrl.repairFolder(itemId: id)
                        }
                    }
                }
            )
            await MainActor.run { importModel.reviewItems.append(reviewItem) }
        }

        await MainActor.run { importModel.importedItems += 1 }
        try Task.checkCancellation()
    }

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

    func addFile(data: Data, to item: any ItemDataAccessable) async throws {
        guard let fileUrlDataController, var fileUrl = item.fileUrl else { return }
        var item = item
        fileUrl.resetData(data)
        do {
            let updated = try await fileUrlDataController.createNewFileUrl(fileId: fileUrl.fileId, unconvertedFileUrl: fileUrl, pathExtension: fileUrl.rawUrl.pathExtension)
            await itemControllable.reset(fileUrl: updated ?? fileUrl, item: &item)
        } catch {
            let module = await MainActor.run { itemControllable.config.module.rawValue }
            Logger.importController.error("Cannot save bookmark \(module, privacy: .public), file stored as data")
            await itemControllable.reset(fileUrl: fileUrl, item: &item)
        }
    }
}

extension InputStream {
    func readHeader() throws -> GmzFileHeader {
        GmzFileHeader(counter: try readCounter(), token: try readCounter(), version: try readCounter())
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

    func readData(size: Int) throws -> Data {
        var readBuffer = [UInt8](repeating: 0, count: size)
        let readCount = read(&readBuffer, maxLength: size)
        guard readCount == readBuffer.count else {
            throw ItemDataImportableError.notEnoughData
        }
        return Data(bytes: readBuffer, count: size)
    }
}
