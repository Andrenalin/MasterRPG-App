// @copyright André Trettin

import Foundation
import os.log
import Observation

@MainActor @Observable
public final class ItemDataImportModel: Sendable {
    public init() {}

    public var gameImporter: Bool = false
    public var importedItems: Int = 0
    public var totalImportingItems: Int = 0
    public var isImportRunning: Bool = false
    public var withOverwrite: Bool = false
}

public protocol ImportControllable: Sendable {
    var itemControllable: any ItemControllable { get }
    var editControllable: any EditControllable { get }
    // overwrite
    var importModel: ItemDataImportModel { get }

    // overwrite
    func additionalImport(from inputStream: InputStream, forceSave: Bool, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws
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

    // Overwrite functions
    func additionalImport(from inputStream: InputStream, forceSave: Bool, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws {}

    /// import the data from a file url, that is calling the stream version
    func importUrl(from url: URL, withOverwrite: Bool = false) -> Task<Void, any Error> {
        let model = importModel
        return Task.detached(priority: .userInitiated) {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            guard let inputStream = InputStream(url: url) else { throw ItemDataImportableError.openError }
            
            inputStream.open()
            defer { inputStream.close() }

            let fileHeader = try inputStream.readHeader()
            // it should be a gmz file and version should be the supported one
            guard fileHeader.token == ExportDataToken.counter.rawValue && fileHeader.version == ExportDataToken.version_2024.rawValue else { throw ItemDataImportableError.notEnoughData }

            let counterTask = Task { @MainActor in
                model.withOverwrite = withOverwrite
                model.importedItems = 0
                model.totalImportingItems = fileHeader.counter
                model.isImportRunning = true
            }
            let _ = await counterTask.result
            
            do {
                try await self.importStream(from: inputStream, forceSave: true,  counterUpdater: self.updaterImport)
                let runningTask = Task { @MainActor in
                    model.isImportRunning = false
                }
                let _ = await runningTask.result
            } catch {
                Task { @MainActor in
                    model.isImportRunning = false
                }
                throw Task.isCancelled ? ItemDataImportableError.cancel : error
            }
        }
    }

    /// import the data from a stream
    func importStream(from inputStream: InputStream, forceSave: Bool, counterUpdater: @Sendable @escaping () async -> Void) async throws {
        guard !Task.isCancelled && inputStream.hasBytesAvailable else { return }

        try await additionalImport(from: inputStream, forceSave: forceSave, counterUpdater: counterUpdater)

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
            try await skip(itemCount: moduleHeader.counter, from: inputStream)
        }
        guard itemCount > 0 else { return }

        await logImport(title: "importStream", count: itemCount)

        let decoder = JSONDecoder()
        var currentFile: Data?

        var counter = 0
        while !Task.isCancelled && counter < itemCount  {
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
                        try await addItem(importedItem: newItem, id: newItem.id, forceSave: forceSave, counterUpdater: counterUpdater)
                    } catch {
                        await logImport(title: "Error: \(error.localizedDescription)", count: 0)
                    }
                    break
                default:
                    throw ItemDataImportableError.unsupportedDataType
                }
            } catch {
                await logImport(title: "Error: \(error.localizedDescription)", count: 0)
            }
        }
    }

    func logImport(title: String, count: Int) async {
        let token = await self.token()
        let counter = await progress()
        Logger.importController.info("\(title, privacy: .public) \(token, privacy: .public) currentItems \(count), importedItems \(counter.count), total: \(counter.total)")
    }
}

private extension ImportControllable {
    @MainActor
    func token() async -> Int {
        itemControllable.config.module.rawValue
    }
    
    @MainActor
    func progress() async -> (count: Int, total: Int) {
        (importModel.importedItems, importModel.totalImportingItems)
    }

    func addItem(importedItem: ModelType, id: UUID, forceSave: Bool, counterUpdater: @escaping () async -> Void) async throws {
        let finalItem: ModelType?
        let itemController = itemControllable
        if await importModel.withOverwrite {
            finalItem = importedItem
        } else {
            finalItem = await itemController.merge(with: importedItem)
        }
        guard let finalItem else {
            await counterUpdater()
            return
        }
        await itemController.replace(model: finalItem, isInsert: true, forceSave: forceSave)
        await editControllable.repairFolder(itemId: id)
        await counterUpdater()
        try Task.checkCancellation()
    }

    func skip(itemCount: Int, from inputStream: InputStream) async throws {
        await logImport(title: "skip", count: itemCount)
        var counter = 0
        while counter < itemCount  {
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

    @Sendable
    func updaterImport() async {
        let model = importModel
        let updateTask = Task { @MainActor in
            model.importedItems += 1
        }
        let _ = await updateTask.result
    }

    func addFile(data: Data, to item: any Observable) async throws {
        guard var item = item as? (any ItemDataAccessable), let fileUrlDataController, var fileUrl = item.fileUrl else { return }
        fileUrl.resetData(data)
        do {
            let updated = try await fileUrlDataController.createNewFileUrl(fileId: fileUrl.fileId, unconvertedFileUrl: fileUrl, pathExtension: fileUrl.rawUrl.pathExtension)
            if updated != fileUrl {
                await itemControllable.reset(fileUrl: updated, item: &item)
            }
        } catch {
            await logImport(title: "Cannot save bookmark the file will be stored as data", count: 0)
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
