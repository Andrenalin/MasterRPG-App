// @copyright André Trettin

import Foundation
import os.log

// MARK: - Game Persistence

public extension ItemControllable {

    /// Persists a game-memory item into the library. The sender's snapshot is merged with the
    /// library copy (or taken as sent, for an `authoritative` delivery such as the game
    /// master's map) and always keeps the local folder placement and visibility. Writing the
    /// raw snapshot lost local edits and moved the item to the sender's folder.
    /// See CODE_AUDIT_Folder §5.23.
    @MainActor func persistFromGame(model: ModelType, authoritative: Bool) {
        guard let model = model as? Model else { return }
        // Bytes that never reached disk are gone at the next launch; the library must not
        // reference them. The delivery's import already requires a stored file, this covers
        // every other way an item gets here. See CODE_AUDIT_21 §5.14.
        if let fileUrl = model.fileUrl, fileUrl.hasUnconvertedData, fileUrl.location == .newCloud {
            Logger.fileStore.error("Not storing game item \(model.id, privacy: .public) in the library: its file was not written to disk")
            return
        }
        guard let library = itemSync(for: model.id, noGame: true) else {
            // A copy: with the game-memory instance itself as the library instance, every later
            // memory-only update of the game changed the library object in place.
            // See CODE_AUDIT_21 §5.31.
            var stored = model.copy()
            stored.parentId = persistMissingFolders(above: model)
            replace(model: stored, isInsert: true, forceSave: true, syncGameMemory: false)
            return
        }
        let previousFile = library.fileUrl
        var persisted: Model
        if authoritative {
            persisted = model.copy()
        } else {
            guard let merged = mergeSync(with: model, forceMerge: true, noGame: true) as? Model else { return }
            persisted = merged
        }
        persisted.parentId = library.parentId
        persisted.displayState = library.displayState
        // The game copy keeps what the game shows; only the library is written.
        replace(model: persisted, isInsert: true, forceSave: true, syncGameMemory: false)
        removeFileReplacedFromGame(previousFile, itemId: model.id)
    }

    /// The folder a new library item goes into. The sender's folders above `model` are matched by
    /// name, level by level, to the library's own: the item goes into the player's folder of that
    /// name. A folder the library lacks is stored as the sender has it (same id, name and
    /// nesting), below the matched one, and listing only what the library holds. Returns the id
    /// to use as the item's parent: the folder it ends in, or `nil` (the root) when its folder is
    /// unknown here. The folders list the item and the folders created for it.
    /// Without this the item was stored under the sender's folder id while the folder itself
    /// stayed in game memory, so it was listed in no folder after the game.
    @MainActor private func persistMissingFolders(above model: Model) -> UUID? {
        guard let parentId = model.parentId else { return nil }
        // From the item's folder up to the first one the library has by id, or to the root.
        var chain: [Model] = []
        var visited: Set<UUID> = [model.id]
        var knownParentId: UUID?
        var nextId: UUID? = parentId
        while let id = nextId {
            guard visited.insert(id).inserted else { break }
            if itemSync(for: id, noGame: true) != nil {
                knownParentId = id
                break
            }
            guard let folder = itemSync(for: id), folder.isFolder else { break }
            chain.append(folder)
            nextId = folder.parentId
        }

        // Outermost first: a folder with the name of the sender's one at the same level is the
        // player's own; below the first one that is not, everything is new.
        var resolvedParentId = knownParentId
        var created: [Model] = []
        var parentOfCreated: UUID?
        for folder in chain.reversed() {
            if created.isEmpty, let own = libraryFolder(named: folder.name, in: resolvedParentId) {
                resolvedParentId = own.id
                continue
            }
            if created.isEmpty { parentOfCreated = resolvedParentId }
            created.append(folder)
            resolvedParentId = folder.id
        }

        // The folders created for the item list only what the library holds.
        let createdIds = Set(created.map(\.id))
        for folder in created {
            var stored = folder.copy()
            stored.parentId = parentOfCreated
            stored.displayState = DisplayStateMask.fullVisible.rawValue
            stored.entries.removeAll { entry in
                !createdIds.contains(entry.childId) && entry.childId != model.id && itemSync(for: entry.childId, noGame: true) == nil
            }
            replace(model: stored, isInsert: true, forceSave: true, syncGameMemory: false)
            if let parentOfCreated { listMember(folder.id, in: parentOfCreated) }
            parentOfCreated = folder.id
        }

        guard let target = resolvedParentId, itemSync(for: target, noGame: true) != nil else { return nil }
        listMember(model.id, in: target)
        return target
    }

    /// The visible library folder called `name` (compared by Unicode form and case) directly
    /// below `parentId`, `nil` is the root. The first by id when there are several.
    @MainActor private func libraryFolder(named name: String, in parentId: UUID?) -> Model? {
        func key(_ name: String) -> String { name.precomposedStringWithCanonicalMapping.lowercased() }
        let wanted = key(name)
        // The match with the smallest id, found in one pass: sorting every item first made each
        // folder level cost a sort of the whole library. See CODE_AUDIT §7.2.
        var match: (id: UUID, model: Model)?
        for id in itemDataModel.items {
            guard match == nil || id.uuidString < match?.id.uuidString ?? "",
                  let candidate = itemSync(for: id, noGame: true),
                  candidate.isFolder, candidate.parentId == parentId,
                  candidate.displayState == DisplayStateMask.fullVisible.rawValue,
                  key(candidate.name) == wanted else { continue }
            match = (id, candidate)
        }
        return match?.model
    }

    /// Lists `childId` in the library folder `folderId` unless it already does.
    @MainActor private func listMember(_ childId: UUID, in folderId: UUID) {
        guard let folder = itemSync(for: folderId, noGame: true),
              !folder.entries.contains(where: { $0.childId == childId }) else { return }
        let updated = folder.copy()
        updated.entries.append(Model.Entry.newChild(id: childId))
        replace(model: updated, isInsert: false, forceSave: true, syncGameMemory: false)
    }

    /// After `persistFromGame` gave a library item the delivered file: removes the file the item
    /// had before, unless the item still references it or another item shares it. Nothing did,
    /// so every stored delivery of a changed file left the old one in iCloud Drive. The
    /// delivered file itself is never removed here; the game still shows it.
    /// See CODE_AUDIT_21 §5.14.
    @MainActor private func removeFileReplacedFromGame(_ previous: FileUrl?, itemId: UUID) {
        guard let previous, let controller = fileUrlDataController,
              let current = itemSync(for: itemId, noGame: true)?.fileUrl,
              !controller.isSameStoredFile(current, previous),
              !isFileUsedElsewhere(previous, excluding: itemId) else { return }
        Task {
            await controller.deleteReplaced(previous, keeping: current)
        }
    }

    /// Removes those of `files` (written for game-memory items) that no library item references.
    /// See CODE_AUDIT_Folder §5.26.
    @MainActor func removeUnreferencedGameFiles(_ files: [FileUrl]) async {
        guard let controller = fileUrlDataController, !files.isEmpty else { return }
        let libraryFiles = libraryFileUrls()
        for file in files where !libraryFiles.contains(where: { controller.isSameStoredFile($0, file) }) {
            await controller.removeStoredFile(file)
        }
    }

    /// Launch cleanup: the files a previous run wrote for game-memory items and could not
    /// remove because the app ended first. See CODE_AUDIT_21 §5.14.
    @MainActor func removeLeftoverGameFiles() async {
        guard let controller = fileUrlDataController else { return }
        await removeUnreferencedGameFiles(controller.model.takeLeftoverGameMemoryFiles())
    }

    /// Persists a folder or collection membership change made in the library UI, also during a
    /// running game, and mirrors only the membership fields into a loaded game-memory copy.
    /// See CODE_AUDIT_Folder §5.21.
    @MainActor func persistMembershipChange(model: ModelType) {
        guard let model = model as? Model else { return }
        replace(model: model, isInsert: false, forceSave: true, syncGameMemory: false)
        if var gameItem = itemDataModel.gameItemData[model.id] as? Model {
            if gameItem.parentId != model.parentId {
                gameItem.parentId = model.parentId
            }
            if model.specialCategory, gameItem.entries != model.entries {
                gameItem.entries = model.entries
            }
        }
    }
}
