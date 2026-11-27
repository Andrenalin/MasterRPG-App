// @copyright André Trettin

import Foundation
import os.log
import Observation

// The imported file handling, split out of ImportControllable.swift. See CODE_AUDIT_29 §9.9.

extension ImportControllable {
    func skip(itemCount: Int, from inputStream: InputStream, importModel: ItemDataImportModel) async throws {
        await logImport(title: "skip", count: itemCount, importModel: importModel)
        var counter = 0
        while counter < itemCount {
            try Task.checkCancellation()
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

    /// Stores the imported bytes of `item`'s file. Returns whether a game delivery reuses the
    /// local file, and the file it wrote (if any) for `settleImportedFile` to clean up after.
    /// - Parameter requiresDurableFile: The file must reach disk or the import of this item
    ///   fails: a library import, or a game delivery that is stored. See CODE_AUDIT_21 §5.14.
    @MainActor func addFile(data: Data, to item: any ItemDataAccessible, forceSave: Bool, requiresDurableFile: Bool) async throws -> (reusesLocalFile: Bool, write: ImportedFileWrite?) {
        guard let fileUrlDataController, var fileUrl = item.fileUrl else { return (false, nil) }
        var item = item
        let module = itemControllable.config.module.rawValue
        // Hashed once, off the main actor; `resetData` below reuses it. See CODE_AUDIT_Folder §7.1.
        let importedHash = await FileUrl.computeContentHash(of: data)
        let localFileUrl = itemControllable.itemSync(for: item.id, noGame: true)?.fileUrl

        // Reuse the existing file when the binary is unchanged — do not write the same file again
        if let existingFileUrl = await reusableExistingFileUrl(for: item.id, importedHash: importedHash, forceSave: forceSave) {
            // A game delivery of a file that is on iCloud Drive but not downloaded here: the
            // iCloud file is left alone (it downloads on its own, `hasDownloadedData` asked for
            // it), and the controller holds the peer's bytes so the game can show them now.
            // Dropping them left the player with a placeholder it could not read.
            var keepsBytesInMemory = false
            if forceSave == false {
                keepsBytesInMemory = await !fileUrlDataController.hasDownloadedData(for: existingFileUrl)
            }
            if keepsBytesInMemory {
                fileUrlDataController.holdPeerData(data, for: existingFileUrl)
            }
            Logger.importController.debug("Import addFile reuses existing file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(existingFileUrl.fileId, privacy: .public) hash=\(importedHash, privacy: .public) forceSave=\(forceSave, privacy: .public) inMemory=\(keepsBytesInMemory, privacy: .public)")
            item.fileUrl = existingFileUrl
            if forceSave == false, let localItem = itemControllable.itemSync(for: item.id, noGame: true) {
                item.parentId = localItem.parentId
            }
            return (forceSave == false, nil)
        }

        if let localFileUrl {
            Logger.importController.warning("Import addFile rewrites existing file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(fileUrl.fileId, privacy: .public) forceSave=\(forceSave, privacy: .public) localHash=\(localFileUrl.contentHash ?? "nil", privacy: .public) importedHash=\(importedHash, privacy: .public) localUrl=\(localFileUrl.rawUrl.absoluteString, privacy: .private) importedUrl=\(fileUrl.rawUrl.absoluteString, privacy: .private)")
        } else {
            Logger.importController.debug("Import addFile writes new file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(fileUrl.fileId, privacy: .public) hash=\(importedHash, privacy: .public) forceSave=\(forceSave, privacy: .public)")
        }

        // Never over another item's file, or over a newer local version of this one: a taken
        // path gets the next free name. See CODE_AUDIT_Folder §5.2.
        fileUrl = try await fileUrlDataController.importDestination(
            for: fileUrl,
            contentHash: importedHash,
            referencedFileUrls: itemControllable.libraryFileUrls()
        )
        fileUrl.resetData(data, contentHash: importedHash)
        do {
            // A library import must not count an item whose file never reached disk; the
            // in-memory fallback is lost at relaunch. Game deliveries keep it.
            // See CODE_AUDIT_Folder §5.26.
            let updated = try await fileUrlDataController.createNewFileUrl(fileId: fileUrl.fileId, unconvertedFileUrl: fileUrl, pathExtension: fileUrl.rawUrl.pathExtension, requireDurableStorage: requiresDurableFile)
            Logger.importController.debug("Import addFile stored imported file module=\(module, privacy: .public) item=\(item.id, privacy: .public) file=\(fileUrl.fileId, privacy: .public) storedUrl=\((updated ?? fileUrl).rawUrl.absoluteString, privacy: .private) storedHash=\((updated ?? fileUrl).contentHash ?? "nil", privacy: .public)")
            let stored = updated ?? fileUrl
            // The write fell back to memory (tvOS cannot store files): item replacement and
            // sync merges drop bytes that sit on the item, so they are held by file id, which
            // every reader (`loadData`, `url(for:)`, `hasDownloadedData`) consults.
            if stored.hasUnconvertedData, stored.location == .newCloud {
                fileUrlDataController.holdPeerData(data, for: stored)
            }
            await itemControllable.reset(fileUrl: stored, item: &item)
            return (false, ImportedFileWrite(written: stored, previous: localFileUrl))
        } catch {
            guard !requiresDurableFile else { throw error }
            Logger.importController.error("Cannot store the delivered file \(module, privacy: .public), keeping it in memory for the game")
            fileUrlDataController.holdPeerData(data, for: fileUrl)
            await itemControllable.reset(fileUrl: fileUrl, item: &item)
            return (false, nil)
        }
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
        // Without a hash the file must be read to compare. A game delivery must not wait on the
        // iCloud download of a file that is not here yet: it reuses the reference and keeps the
        // peer's bytes in memory (see `addFile`); nothing is written in game mode.
        if forceSave == false, await fileUrlDataController?.hasLocalData(for: existingFileUrl) == true,
           await fileUrlDataController?.hasDownloadedData(for: existingFileUrl) == false {
            return existingFileUrl
        }
        // Streamed from disk off the main actor instead of loading the whole file to hash it.
        // See CODE_AUDIT_Folder §7.1.
        guard let existingHash = try? await fileUrlDataController?.contentHash(for: existingFileUrl),
              existingHash == importedHash else { return nil }
        guard forceSave else { return existingFileUrl }

        existingFileUrl.resetContentHash(existingHash)
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
