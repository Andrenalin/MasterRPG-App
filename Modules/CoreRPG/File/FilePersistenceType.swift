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
    private let priority: TaskPriority

    init(name: String, persistence: FilePersistenceType, dataExtension: String? = nil, priority: TaskPriority = .userInitiated) {
        self.name = name
        self.dataExtension = dataExtension
        self.type = persistence
        self.model = FilePersistenceModel()
        self.priority = priority
    }
}

// MARK: Manage Data

extension FilePersistenceController {
    func load() async -> [DataModel] {
        guard type != .memory else { return await model.cache }
        let oldUrl = oldFileURL
        let loadUrl = fileURL
        let backgroundTask = Task.detached(priority: priority) {
            do {
                try await migrateOldFile(oldUrl: oldUrl, newUrl: loadUrl)
                let exists = FileManager.default.fileExists(atPath: loadUrl.relativePath)
                if !exists {
                    try FileManager.default.createDirectory(at: loadUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FilePersistenceController.saveModel(data: [], into: loadUrl)
                }
                let data = try Data(contentsOf: loadUrl)

                let decoder = JSONDecoder()
                let loadedData = try decoder.decode([DataModel].self, from: data)
                return loadedData
            } catch {
                Logger.filePersistenceController.error("Error loading data \(error.localizedDescription, privacy: .public)")
            }
            return []
        }
        return await backgroundTask.value
    }

    func save(data: [DataModel]) async {
        guard type != .memory else {
            await model.setCache(update: data)
            return
        }
        let saveURL = fileURL
        let backgroundTask = Task.detached(priority: priority) {
            do {
                try FilePersistenceController.saveModel(data: data, into: saveURL)
            } catch {
                Logger.filePersistenceController.error("Error saving data \(error.localizedDescription, privacy: .public)")
            }
        }
        let _ = await backgroundTask.result
    }

    func remove() async {
        guard type != .memory else {
            await model.setCache(update: [])
            return
        }
        let removeURL = fileURL
        let backgroundTask = Task.detached(priority: .userInitiated) {
            try? FileManager.default.removeItem(at: removeURL)
        }
        let _ = await backgroundTask.value
    }
}

// MARK: external data in files

extension FilePersistenceController {
    func loadData(for uuid: String) async throws -> Data? {
        guard let url = try dataURL(for: uuid) else { return nil }
        let loadTask = Task.detached(priority: priority) {
            try Data(contentsOf: url)
        }
        return try await loadTask.value
    }

    func saveData(_ data: Data, for uuid: String) async throws {
        guard let url = try dataURL(for: uuid) else { return }
        let loadTask = Task.detached(priority: priority) {
            try data.write(to: url)
        }
        let _ = await loadTask.result
    }

    func removeData(for uuid: String) async throws {
        guard let url = try dataURL(for: uuid) else { return }
        let loadTask = Task.detached(priority: priority) {
            try FileManager.default.removeItem(at: url)
        }
        let _ = await loadTask.result
    }
}

private extension FilePersistenceController {
    static func saveModel(data: [DataModel], into fileURL: URL) throws {
        let encoder = JSONEncoder()
        guard let encodedData = try? encoder.encode(data) else { return }
        try encodedData.write(to: fileURL)
    }

    func dataURL(for uuid: String) throws -> URL? {
        var documentsURL = URL.documentsDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        documentsURL.appendPathComponent("\(uuid)\(dataExtension ?? "")")
        return documentsURL
    }

    var fileURL: URL {
        FileManager.groupURL.appendingPathComponent("\(name).json")
    }

    var oldFileURL: URL {
        URL.documentsDirectory.appendingPathComponent("\(name).json")
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
