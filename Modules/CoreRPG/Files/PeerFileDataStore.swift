// @copyright André Trettin

import Foundation
import Synchronization

/// Bytes game peers sent for files not downloaded from iCloud on this device, by file id.
///
/// A read-only overlay for game readers only: mutating file operations (delete, move, copy)
/// always act on the file's real location. The store is process-wide (file ids are unique across
/// modules), bounded by `maximumBytes` (oldest entries are evicted first) and emptied when the
/// game ends. See CODE_AUDIT_20 §5.3.
final class PeerFileDataStore: Sendable {
    static let shared = PeerFileDataStore()

    /// Upper bound of all bytes held at once. A single larger file is still held, alone.
    static let defaultMaximumBytes = ByteLimits.maximumSourceFileBytes

    private let maximumBytes: Int

    init(maximumBytes: Int = PeerFileDataStore.defaultMaximumBytes) {
        self.maximumBytes = maximumBytes
    }

    private struct State {
        var entries: [UUID: Entry] = [:]
        var order: [UUID] = []
        var totalBytes = 0
        var nextGeneration = 0
    }

    private struct Entry {
        let data: Data
        let generation: Int
    }

    private let state = Mutex(State())

    func data(for fileId: UUID) -> Data? {
        state.withLock { $0.entries[fileId]?.data }
    }

    /// The held bytes together with a generation that changes whenever they are replaced, read
    /// under one lock so a reader never pairs old bytes with a newer generation.
    func snapshot(for fileId: UUID) -> (data: Data, generation: Int)? {
        state.withLock { state in
            state.entries[fileId].map { ($0.data, $0.generation) }
        }
    }

    func hold(_ data: Data, for fileId: UUID) {
        let evicted = state.withLock { state -> [UUID] in
            var evicted: [UUID] = []
            if let previous = state.entries.removeValue(forKey: fileId) {
                state.totalBytes -= previous.data.count
                state.order.removeAll { $0 == fileId }
                if previous.data != data { evicted.append(fileId) }
            }
            while state.totalBytes + data.count > maximumBytes, let oldest = state.order.first {
                state.order.removeFirst()
                if let entry = state.entries.removeValue(forKey: oldest) {
                    state.totalBytes -= entry.data.count
                }
                evicted.append(oldest)
            }
            state.nextGeneration += 1
            state.entries[fileId] = Entry(data: data, generation: state.nextGeneration)
            state.order.append(fileId)
            state.totalBytes += data.count
            return evicted
        }
        for id in evicted { Self.removeTemporaryCopy(of: id) }
    }

    func remove(_ fileId: UUID) {
        let removed = state.withLock { state -> Bool in
            guard let entry = state.entries.removeValue(forKey: fileId) else { return false }
            state.totalBytes -= entry.data.count
            state.order.removeAll { $0 == fileId }
            return true
        }
        if removed { Self.removeTemporaryCopy(of: fileId) }
    }

    func removeAll() {
        let ids = state.withLock { state -> [UUID] in
            let ids = Array(state.entries.keys)
            state = State(nextGeneration: state.nextGeneration)
            return ids
        }
        for id in ids { Self.removeTemporaryCopy(of: id) }
    }

    /// The name every temporary copy of a peer's file starts with, so `removeTemporaryCopy` finds
    /// what `FileUrlDataController.heldPeerFileUrl` wrote. See CODE_AUDIT §9.16.
    static let temporaryCopyPrefix = "peer-"

    static func temporaryCopyName(of fileId: UUID) -> String {
        "\(temporaryCopyPrefix)\(fileId.uuidString)"
    }

    private static func removeTemporaryCopy(of fileId: UUID) {
        let prefix = temporaryCopyName(of: fileId)
        let directory = URL.temporaryDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
