// @copyright André Trettin

import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// A file in a module's iCloud folder, by its path below the module folder.
struct CloudScanFile: Sendable, Hashable {
    /// Folder names and the file name, as stored. A not yet downloaded file (iCloud lists it as
    /// the hidden placeholder `.name.pdf.icloud`) carries its real name.
    let components: [String]
    /// Only a placeholder is listed: the bytes are not on this device, so they cannot be hashed.
    var isPlaceholder = false

    var fileName: String { components.last ?? "" }
    var folderNames: [String] { Array(components.dropLast()) }

    /// The item name: the file name without its extension. `EditControllable.folderPath` builds
    /// the stored path back from the item names, and the move appends the extension again.
    var itemName: String {
        let name = fileName
        let withoutExtension = (name as NSString).deletingPathExtension
        return (withoutExtension.isEmpty ? name : withoutExtension).precomposedStringWithCanonicalMapping
    }

    /// The stored reference of the file, as `FileUrlDataController` writes it: below the module
    /// folder, with a leading slash.
    var storedUrl: URL {
        var url = URL(string: "/") ?? URL(filePath: "/")
        components.forEach { url.append(path: $0) }
        return url
    }
}

/// What the sync with a module's iCloud folder found. Every entry has the id of the item it is
/// about (for an addition: the id of the item to create), which is what the user deselects by.
struct CloudScanPlan: Sendable, Equatable {
    struct Folder: Sendable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let parentId: UUID?
        /// Folder names from the module folder down to this folder.
        let path: [String]
    }

    /// A file that no item references: gets an item.
    struct Item: Sendable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let parentId: UUID?
        let file: CloudScanFile
    }

    /// An item whose file is gone from iCloud.
    struct Removal: Sendable, Equatable, Identifiable {
        let id: UUID
        let name: String
        /// The path the item's file had.
        let path: [String]
    }

    /// An item that moves into the folder of its file.
    struct Move: Sendable, Equatable, Identifiable {
        let id: UUID
        let name: String
        /// The file as it was moved on iCloud, or `nil` when the file is where the item says and
        /// only the item changes its folder.
        let file: CloudScanFile?
        /// Where the item is now: the old file path, or the item's folder path in the app.
        let from: [String]
        /// Where it goes: the new file path, or the folder path of the file.
        let to: [String]
        /// The folder the item goes into; `nil` is the module root.
        let parentId: UUID?
    }

    /// New folders for the additions and the moves, parents before their children.
    var folders: [Folder] = []
    var items: [Item] = []
    var moves: [Move] = []
    var removals: [Removal] = []
    /// Most of the items with a file lost it. The iCloud folder is probably still syncing.
    var mostFilesMissing = false

    var isEmpty: Bool { folders.isEmpty && items.isEmpty && moves.isEmpty && removals.isEmpty }

    /// The moves that follow a file moved on iCloud; the others only change the item's folder.
    var movedFiles: [Move] { moves.filter { $0.file != nil } }
    var movedItems: [Move] { moves.filter { $0.file == nil } }

    /// The ids of every entry the user can select.
    var selectableIds: [UUID] { items.map(\.id) + moves.map(\.id) + removals.map(\.id) }

    /// The plan without what the user deselected, and only with the new folders the rest needs.
    func restricted(toDeselected deselected: Set<UUID>) -> CloudScanPlan {
        var result = self
        result.items.removeAll { deselected.contains($0.id) }
        result.moves.removeAll { deselected.contains($0.id) }
        result.removals.removeAll { deselected.contains($0.id) }

        let foldersById = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var needed: Set<UUID> = []
        var pending = result.items.compactMap(\.parentId) + result.moves.compactMap(\.parentId)
        while let id = pending.popLast() {
            guard let folder = foldersById[id], needed.insert(id).inserted, let parentId = folder.parentId else { continue }
            pending.append(parentId)
        }
        result.folders.removeAll { !needed.contains($0.id) }
        return result
    }
}

/// One library item as far as the scan needs it. A value, so the planning needs no model type.
struct CloudScanExistingItem: Sendable, Equatable {
    let id: UUID
    let name: String
    let parentId: UUID?
    let isFolder: Bool
    let isTrashed: Bool
    /// The stored file below the module folder, when the item references one.
    let fileComponents: [String]?
    /// The content hash of the item's file, when it has one. Picker-added files have none.
    var contentHash: String?
}

enum CloudFolderScan {
    // MARK: - Ids

    /// The id of the item or folder for `path` in `module`. Derived from the path, not random:
    /// two devices that scan the same iCloud folder before CloudKit syncs create the same item,
    /// and CloudKit merges the two instead of keeping both. SHA-256, never `hashValue`, which
    /// differs per run and per device. The path is Unicode-normalised so a name stored
    /// decomposed on one device and precomposed on another gets one id. Shaped like a UUID v5.
    static func derivedId(module: String, path: [String], isFolder: Bool) -> UUID {
        let kind = isFolder ? "folder" : "item"
        let names = path.map { $0.precomposedStringWithCanonicalMapping }
        let input = ([kind, module] + names).joined(separator: "/")
        var bytes = Array(SHA256.hash(data: Data(input.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// A path compared case-insensitively and Unicode-normalised, like the file system does.
    static func key(_ components: [String]) -> String {
        components.map { $0.precomposedStringWithCanonicalMapping.lowercased() }.joined(separator: "/")
    }

    // MARK: - Listing

    /// The files below `moduleUrl` whose type is one of `fileTypes`, in path order. Placeholders of
    /// files that are only in iCloud are listed with their real name. Hidden files and folders
    /// are skipped. `nil` when the module folder cannot be read at all, which is not the same as a
    /// folder without files: with iCloud unavailable every item would look like its file is gone.
    /// `@concurrent`: a large iCloud folder is walked on disk.
    @concurrent
    static func files(below moduleUrl: URL, fileTypes: [UTType]) async -> [CloudScanFile]? {
        var found: [CloudScanFile] = []
        var pending: [(url: URL, components: [String])] = [(moduleUrl, [])]
        while let (folder, folderComponents) = pending.popLast() {
            guard !Task.isCancelled else { return nil }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else {
                if folderComponents.isEmpty { return nil }
                continue
            }
            for url in contents {
                let name = url.lastPathComponent
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory {
                    if !name.hasPrefix(".") {
                        pending.append((url, folderComponents + [name]))
                    }
                    continue
                }
                guard let realName = realFileName(name), matches(realName, fileTypes: fileTypes) else { continue }
                found.append(CloudScanFile(components: folderComponents + [realName], isPlaceholder: realName != name))
            }
        }
        return found.sorted { key($0.components) < key($1.components) }
    }

    /// `name` of a listed file, with the iCloud placeholder wrapping (`.name.icloud`) removed;
    /// `nil` for hidden files such as `.DS_Store`.
    static func realFileName(_ listed: String) -> String? {
        if listed.hasPrefix("."), listed.hasSuffix(".icloud"), listed.count > ".icloud".count + 1 {
            return String(listed.dropFirst().dropLast(".icloud".count))
        }
        return listed.hasPrefix(".") ? nil : listed
    }

    static func matches(_ fileName: String, fileTypes: [UTType]) -> Bool {
        let fileExtension = (fileName as NSString).pathExtension
        guard !fileExtension.isEmpty, let type = UTType(filenameExtension: fileExtension) else { return false }
        return fileTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Hashes

    /// The files whose hash decides whether they are a moved file: unreferenced files that carry
    /// the name of an item with a hash whose own file is gone, and that are downloaded.
    static func hashCandidates(files: [CloudScanFile], existing: [CloudScanExistingItem]) -> [CloudScanFile] {
        let analysis = analyze(files: files, existing: existing)
        let names = Set(analysis.missing.filter { $0.contentHash != nil }.compactMap { $0.fileComponents?.last }.map { key([$0]) })
        return analysis.unreferenced.filter { !$0.isPlaceholder && names.contains(key([$0.fileName])) }
    }

    /// The content hash by `key` of each downloaded file in `files`. `@concurrent`: reads the files.
    @concurrent
    static func hashes(of files: [CloudScanFile], below moduleUrl: URL) async -> [String: String] {
        var result: [String: String] = [:]
        for file in files where !file.isPlaceholder {
            guard !Task.isCancelled else { break }
            var url = moduleUrl
            file.components.forEach { url.append(path: $0) }
            if let hash = try? await FileManager.default.contentHash(coordinatingAccessAt: url) {
                result[key(file.components)] = hash
            }
        }
        return result
    }

    // MARK: - Planning

    private struct Analysis {
        /// Items with a file that no listed file matches.
        var missing: [CloudScanExistingItem] = []
        /// Listed files no item references.
        var unreferenced: [CloudScanFile] = []
        var referencedKeys: Set<String> = []
        var fileBackedCount = 0
    }

    private static func analyze(files: [CloudScanFile], existing: [CloudScanExistingItem]) -> Analysis {
        let listedKeys = Set(files.map { key($0.components) })
        var analysis = Analysis()
        analysis.referencedKeys = Set(existing.compactMap { $0.fileComponents.map(key) })
        analysis.missing = existing
            .filter { item in
                guard !item.isTrashed, let components = item.fileComponents else { return false }
                return !listedKeys.contains(key(components))
            }
            .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
        analysis.fileBackedCount = existing.filter { !$0.isTrashed && $0.fileComponents != nil }.count
        var seen: Set<String> = []
        analysis.unreferenced = files
            .sorted { key($0.components) < key($1.components) }
            .filter { file in
                let fileKey = key(file.components)
                return !analysis.referencedKeys.contains(fileKey) && seen.insert(fileKey).inserted
            }
        return analysis
    }

    /// What to change so that the library matches the files in `files`: items for files without
    /// one, items that follow their file when it was moved on iCloud or sits in another folder,
    /// and items whose file is gone. Existing folders with the same name path are reused.
    /// Pure: the result depends only on the arguments.
    ///
    /// - Parameter hashes: the content hash by `key` of the files `hashCandidates` named.
    static func plan(
        files: [CloudScanFile],
        existing: [CloudScanExistingItem],
        module: String,
        hashes: [String: String] = [:]
    ) -> CloudScanPlan {
        let analysis = analyze(files: files, existing: existing)
        let existingIds = Set(existing.map(\.id))
        let byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var folderIds = existingFolderIds(existing)
        var plan = CloudScanPlan()

        /// The folder for `path`, created (with its missing ancestors) when it does not exist.
        func ensureFolder(_ names: [String]) -> UUID? {
            var parentId: UUID?
            var path: [String] = []
            for name in names {
                path.append(name)
                let folderKey = key(path)
                if let id = folderIds[folderKey] {
                    parentId = id
                    continue
                }
                let derived = derivedId(module: module, path: path, isFolder: true)
                // An item with that id exists but is not this folder (renamed, moved or trashed):
                // the new folder gets an id of its own.
                let id = existingIds.contains(derived) ? UUID() : derived
                plan.folders.append(.init(id: id, name: name.precomposedStringWithCanonicalMapping, parentId: parentId, path: path))
                folderIds[folderKey] = id
                parentId = id
            }
            return parentId
        }

        // A file that went to another folder on iCloud: its item's old path is gone and a file
        // of the same name (and hash) is there instead.
        let pairs = movedFilePairs(missing: analysis.missing, candidates: analysis.unreferenced, hashes: hashes)
        for item in analysis.missing {
            guard let file = pairs[item.id], let oldPath = item.fileComponents else { continue }
            plan.moves.append(.init(
                id: item.id, name: item.name, file: file, from: oldPath, to: file.components,
                parentId: ensureFolder(file.folderNames)
            ))
        }
        let movedKeys = Set(pairs.values.map { key($0.components) })

        // Items that kept their file but sit in another folder than the file.
        let fileKeys = Set(files.map { key($0.components) })
        for item in existing.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard !item.isTrashed, let components = item.fileComponents, fileKeys.contains(key(components)),
                  let appFolder = appFolderNames(of: item, in: byId) else { continue }
            let fileFolder = Array(components.dropLast())
            // By name path: two folders of one name are not a reason to move an item.
            guard key(appFolder) != key(fileFolder) else { continue }
            let target: UUID?
            if fileFolder.isEmpty {
                target = nil
            } else if let id = folderIds[key(fileFolder)] {
                target = id
            } else {
                target = ensureFolder(fileFolder)
            }
            guard target != item.parentId else { continue }
            plan.moves.append(.init(id: item.id, name: item.name, file: nil, from: appFolder, to: fileFolder, parentId: target))
        }

        for item in analysis.missing where pairs[item.id] == nil {
            plan.removals.append(.init(id: item.id, name: item.name, path: item.fileComponents ?? []))
        }
        plan.mostFilesMissing = plan.removals.count >= 3 && plan.removals.count * 2 > analysis.fileBackedCount

        for file in analysis.unreferenced where !file.itemName.isEmpty && !movedKeys.contains(key(file.components)) {
            let parentId = ensureFolder(file.folderNames)
            let derived = derivedId(module: module, path: file.components, isFolder: false)
            let id = existingIds.contains(derived) ? UUID() : derived
            plan.items.append(.init(id: id, name: file.itemName, parentId: parentId, file: file))
        }
        return plan
    }

    /// The moved file of each item whose file is gone, by item id. A file is the match when it has
    /// the item's file name and, where both hashes are known, the item's content hash. An item
    /// without a hash, or a file that is not downloaded and cannot be hashed, matches by name; a
    /// name with several candidates needs the hash to tell them apart. A file two items claim
    /// belongs to neither.
    private static func movedFilePairs(
        missing: [CloudScanExistingItem],
        candidates: [CloudScanFile],
        hashes: [String: String]
    ) -> [UUID: CloudScanFile] {
        let byName = Dictionary(grouping: candidates, by: { key([$0.fileName]) })
        var picks: [UUID: CloudScanFile] = [:]
        for item in missing {
            guard let name = item.fileComponents?.last else { continue }
            let compatible = (byName[key([name])] ?? []).filter { file in
                guard let itemHash = item.contentHash, let fileHash = hashes[key(file.components)] else { return true }
                return itemHash == fileHash
            }
            if compatible.count == 1 {
                picks[item.id] = compatible[0]
            } else if compatible.count > 1, let itemHash = item.contentHash {
                let exact = compatible.filter { hashes[key($0.components)] == itemHash }
                if exact.count == 1 {
                    picks[item.id] = exact[0]
                }
            }
        }
        var claimants: [String: Int] = [:]
        picks.values.forEach { claimants[key($0.components), default: 0] += 1 }
        return picks.filter { claimants[key($0.value.components)] == 1 }
    }

    /// The names of the folders `item` is in, from the module root down. `nil` when it sits in
    /// something that is not a visible folder (a collection, a trashed or missing parent): the
    /// folder of its file says nothing about where such an item belongs.
    private static func appFolderNames(of item: CloudScanExistingItem, in byId: [UUID: CloudScanExistingItem]) -> [String]? {
        var names: [String] = []
        var visited: Set<UUID> = [item.id]
        var parentId = item.parentId
        while let id = parentId {
            guard visited.insert(id).inserted, let parent = byId[id], parent.isFolder, !parent.isTrashed else { return nil }
            names.append(parent.name)
            parentId = parent.parentId
        }
        return names.reversed()
    }

    /// The visible folders of the library by name path.
    private static func existingFolderIds(_ existing: [CloudScanExistingItem]) -> [String: UUID] {
        let byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: UUID] = [:]
        for folder in existing.sorted(by: { $0.id.uuidString < $1.id.uuidString }) where folder.isFolder && !folder.isTrashed {
            var names: [String] = []
            var visited: Set<UUID> = []
            var current: CloudScanExistingItem? = folder
            var isVisible = true
            while let item = current, visited.insert(item.id).inserted {
                if item.isTrashed { isVisible = false }
                names.append(item.name)
                current = item.parentId.flatMap { byId[$0] }
            }
            guard isVisible else { continue }
            let pathKey = key(Array(names.reversed()))
            if result[pathKey] == nil {
                result[pathKey] = folder.id
            }
        }
        return result
    }
}
