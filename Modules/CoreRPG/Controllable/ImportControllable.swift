// @copyright André Trettin

import Foundation
import os.log
import Observation

@MainActor @Observable
public final class ItemDataImportModel {
    public init() {}

    public var importedItems: Int = 0
    public var totalImportingItems: Int = 0
    public var isImportRunning: Bool = false
    public var withOverwrite: Bool = false
}

public struct ImportConfiguration: Sendable {
    public let importModel: ItemDataImportModel

    public init(importModel: ItemDataImportModel) {
        self.importModel = importModel
    }
}

public protocol ImportControllable: Sendable {
    var itemControllable: any ItemControllable { get }
    var editControllable: any EditControllable { get }

    @MainActor func makeImportConfiguration() -> ImportConfiguration

    // overwrite
    func additionalImport(from inputStream: InputStream, forceSave: Bool, configuration: ImportConfiguration, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws
}

public enum ItemDataImportableError: Error {
    case openError
    case notEnoughData
    case unsupportedDataType
    case fileWithoutItem
    case cancel
}

public extension ImportControllable {
    // Default: creates a fresh model — module controllers are always called with configuration from adventure
    @MainActor func makeImportConfiguration() -> ImportConfiguration {
        ImportConfiguration(importModel: ItemDataImportModel())
    }

    var fileUrlDataController: FileUrlDataController? { itemControllable.fileUrlDataController }

    // Overwrite functions
    func additionalImport(from inputStream: InputStream, forceSave: Bool, configuration: ImportConfiguration, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws {}

    /// import the data from a file url, that is calling the stream version
    func importUrl(from url: URL, withOverwrite: Bool = false) -> Task<Void, any Error> {
        return Task.detached(priority: .userInitiated) {
            let configuration = await MainActor.run { self.makeImportConfiguration() }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            guard let inputStream = InputStream(url: url) else { throw ItemDataImportableError.openError }

            inputStream.open()
            defer { inputStream.close() }

            let fileHeader = try inputStream.readHeader()
            // it should be a gmz file and version should be the supported one
            guard fileHeader.token == ExportDataToken.counter.rawValue && fileHeader.version == ExportDataToken.version_2024.rawValue else { throw ItemDataImportableError.notEnoughData }

            await MainActor.run {
                configuration.importModel.withOverwrite = withOverwrite
                configuration.importModel.importedItems = 0
                configuration.importModel.totalImportingItems = fileHeader.counter
                configuration.importModel.isImportRunning = true
            }

            let updater: @MainActor @Sendable () async -> Void = { [configuration] in
                configuration.importModel.importedItems += 1
            }

            do {
                try await self.importStream(from: inputStream, forceSave: true, configuration: configuration, counterUpdater: updater)
                await MainActor.run { configuration.importModel.isImportRunning = false }
            } catch {
                await MainActor.run { configuration.importModel.isImportRunning = false }
                throw Task.isCancelled ? ItemDataImportableError.cancel : error
            }
        }
    }

    /// import the data from a stream
    func importStream(from inputStream: InputStream, forceSave: Bool, configuration: ImportConfiguration, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws {
        guard !Task.isCancelled && inputStream.hasBytesAvailable else { return }

        try await additionalImport(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)

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
            try await skip(itemCount: moduleHeader.counter, from: inputStream, configuration: configuration)
        }
        guard itemCount > 0 else { return }

        await logImport(title: "importStream", count: itemCount, configuration: configuration)

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
                        try await addItem(importedItem: newItem, id: newItem.id, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
                    } catch {
                        await logImport(title: "Error: \(error.localizedDescription)", count: 0, configuration: configuration)
                    }
                    break
                default:
                    throw ItemDataImportableError.unsupportedDataType
                }
            } catch {
                await logImport(title: "Error: \(error.localizedDescription)", count: 0, configuration: configuration)
            }
        }

        guard !Task.isCancelled else { return }
        let cc = ConvertController(itemController: itemControllable, editController: editControllable)
        await cc.repairHiddenAndFolders(reportModel: ValidateRepairModel())
    }

    // Convenience without configuration — for game networking imports (no progress tracking)
    func importStream(from inputStream: InputStream, forceSave: Bool, counterUpdater: @MainActor @Sendable @escaping () async -> Void) async throws {
        let configuration = await MainActor.run { makeImportConfiguration() }
        try await importStream(from: inputStream, forceSave: forceSave, configuration: configuration, counterUpdater: counterUpdater)
    }

    func logImport(title: String, count: Int, configuration: ImportConfiguration) async {
        let (token, importedItems, totalItems) = await MainActor.run {
            (itemControllable.config.module.rawValue, configuration.importModel.importedItems, configuration.importModel.totalImportingItems)
        }
        Logger.importController.info("\(title, privacy: .public) \(token, privacy: .public) currentItems \(count), importedItems \(importedItems), total: \(totalItems)")
    }
}

private extension ImportControllable {
    @MainActor
    func token() async -> Int {
        itemControllable.config.module.rawValue
    }

    func addItem(importedItem: ModelType, id: UUID, forceSave: Bool, configuration: ImportConfiguration, counterUpdater: @MainActor @escaping () async -> Void) async throws {
        let finalItem: ModelType?
        let itemController = itemControllable
        if await configuration.importModel.withOverwrite {
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

    func skip(itemCount: Int, from inputStream: InputStream, configuration: ImportConfiguration) async throws {
        await logImport(title: "skip", count: itemCount, configuration: configuration)
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

    func addFile(data: Data, to item: any Observable) async throws {
        guard var item = item as? (any ItemDataAccessable), let fileUrlDataController, var fileUrl = item.fileUrl else { return }
        fileUrl.resetData(data)
        do {
            let updated = try await fileUrlDataController.createNewFileUrl(fileId: fileUrl.fileId, unconvertedFileUrl: fileUrl, pathExtension: fileUrl.rawUrl.pathExtension)
            if updated != fileUrl {
                await itemControllable.reset(fileUrl: updated, item: &item)
            }
        } catch {
            let module = await MainActor.run { itemControllable.config.module.rawValue }
            Logger.importController.info("Cannot save bookmark \(module, privacy: .public), file stored as data")
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
