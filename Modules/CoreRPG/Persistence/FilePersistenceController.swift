// @copyright André Trettin

import Foundation
import os.log

public enum FilePersistenceType: Sendable {
    case store
    case memory
}

struct DataModel: Codable, Sendable {
    let id: UUID
    let data: Data
}

struct FilePersistenceController: Sendable {
    private let name: String
    private let type: FilePersistenceType
    private let dataExtension: String?
    private let model: FilePersistenceModel

    init(name: String, persistence: FilePersistenceType, dataExtension: String? = nil) {
        self.name = name
        self.dataExtension = dataExtension
        self.type = persistence
        self.model = FilePersistenceModel()
    }
}

// MARK: Manage Data

// `@concurrent`: file I/O and JSON decoding used to run on the (often main-actor) caller's
// executor at launch, once per file module. See CODE_AUDIT_18 §7.4.
extension FilePersistenceController {
    @concurrent
    func load() async -> [DataModel] {
        guard type != .memory else { return await model.cache }
        let oldUrl = oldFileUrl
        let loadUrl = fileUrl
        do {
            try await migrateOldFile(oldUrl: oldUrl, newUrl: loadUrl)
            let exists = FileManager.default.fileExists(atPath: loadUrl.relativePath)
            if !exists {
                try FileManager.default.createDirectory(at: loadUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FilePersistenceController.saveModel(data: [], into: loadUrl)
            }
            let data = try Data(contentsOf: loadUrl)

            let decoder = JSONDecoder()
            do {
                return try decoder.decode([DataModel].self, from: data)
            } catch {
                // Treating an undecodable file as "empty" would let the next save overwrite it and
                // lose everything that was still recoverable; keep it aside instead.
                // See CODE_AUDIT_15 §5.5.
                let backupUrl = loadUrl.appendingPathExtension("corrupt")
                try? FileManager.default.removeItem(at: backupUrl)
                try? FileManager.default.moveItem(at: loadUrl, to: backupUrl)
                Logger.filePersistenceController.error("Stored file is undecodable, kept as \(backupUrl.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return []
            }
        } catch {
            Logger.filePersistenceController.error("Error loading data \(error.localizedDescription, privacy: .public)")
        }
        return []
    }

    @concurrent
    func save(data: [DataModel]) async {
        guard type != .memory else {
            await model.setCache(update: data)
            return
        }
        let saveUrl = fileUrl
        do {
            try FilePersistenceController.saveModel(data: data, into: saveUrl)
        } catch {
            Logger.filePersistenceController.error("Error saving data \(error.localizedDescription, privacy: .public)")
        }
    }

    @concurrent
    func remove() async {
        guard type != .memory else {
            await model.setCache(update: [])
            return
        }
        let removeUrl = fileUrl
        try? FileManager.default.removeItem(at: removeUrl)
    }
}

// MARK: external data in files

extension FilePersistenceController {
    func loadData(for uuid: String) async throws -> Data? {
        guard let url = try dataUrl(for: uuid) else { return nil }
        return try Data(contentsOf: url)
    }

    func saveData(_ data: Data, for uuid: String) async throws {
        guard let url = try dataUrl(for: uuid) else { return }
        try data.write(to: url)
    }

    func removeData(for uuid: String) async throws {
        guard let url = try dataUrl(for: uuid) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

private extension FilePersistenceController {
    static func saveModel(data: [DataModel], into fileUrl: URL) throws {
        let encodedData = try JSONEncoder().encode(data)
        // Atomic: a kill mid-write must not leave a truncated file. See CODE_AUDIT_15 §5.5.
        try encodedData.write(to: fileUrl, options: .atomic)
    }

    func dataUrl(for uuid: String) throws -> URL? {
        var documentsUrl = URL.documentsDirectory.appending(path: name)
        try FileManager.default.createDirectory(at: documentsUrl, withIntermediateDirectories: true)
        documentsUrl.appendPathComponent("\(uuid)\(dataExtension ?? "")")
        return documentsUrl
    }

    // Falls back to `URL.documentsDirectory` (the same root `oldFileUrl` already uses)
    // when the App Group entitlement/provisioning profile doesn't grant access, rather
    // than crashing — see CODE_AUDIT §5.1. Widgets sharing this data won't see it in
    // that edge case, but the app keeps functioning locally instead of crashing at launch.
    var fileUrl: URL {
        (FileManager.groupURL ?? URL.documentsDirectory).appending(path: "\(name).json")
    }

    var oldFileUrl: URL {
        URL.documentsDirectory.appending(path: "\(name).json")
    }

    func migrateOldFile(oldUrl: URL, newUrl: URL) async throws {
        guard FileManager.default.fileExists(atPath: oldUrl.relativePath) else { return }
        try await FileManager.default.moveItem(coordinatingAccessFrom: oldUrl, to: newUrl)
    }
}

private actor FilePersistenceModel {
    private(set) var cache: [DataModel] = []

    func setCache(update: [DataModel]) {
        cache = update
    }
}

private extension Logger {
    static let filePersistenceController = Logger(subsystem: subsystem, category: "FilePersistenceController")
}
