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
        // The replaced bytes are compared with the new ones after the lock is released: a
        // byte-wise comparison of two large files must not block every other reader. §7.32.
        let (evicted, previousData) = state.withLock { state -> ([UUID], Data?) in
            var evicted: [UUID] = []
            var previousData: Data?
            if let previous = state.entries.removeValue(forKey: fileId) {
                state.totalBytes -= previous.data.count
                state.order.removeAll { $0 == fileId }
                previousData = previous.data
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
            return (evicted, previousData)
        }
        // The compare (up to `maximumSourceFileBytes`) and the directory listing run off the
        // caller, which is the main-actor `addFile` of a game delivery. See CODE_AUDIT_29 §3.6.
        guard previousData != nil || !evicted.isEmpty else { return }
        // A copy of the generation that is held when the task runs is kept: a reader may have
        // written it for the new bytes in the meantime.
        Task.detached(priority: .utility) { [self] in
            var stale = evicted
            if let previousData, previousData != data { stale.append(fileId) }
            let current = state.withLock { state in
                stale.compactMap { id in state.entries[id].map { (id, $0.generation) } }
            }
            Self.removeTemporaryCopies(of: stale, keeping: Dictionary(current, uniquingKeysWith: { first, _ in first }))
        }
    }

    func remove(_ fileId: UUID) {
        let removed = state.withLock { state -> Bool in
            guard let entry = state.entries.removeValue(forKey: fileId) else { return false }
            state.totalBytes -= entry.data.count
            state.order.removeAll { $0 == fileId }
            return true
        }
        if removed { Self.removeTemporaryCopies(of: [fileId]) }
    }

    func removeAll() {
        let ids = state.withLock { state -> [UUID] in
            let ids = Array(state.entries.keys)
            state = State(nextGeneration: state.nextGeneration)
            return ids
        }
        Self.removeTemporaryCopies(of: ids)
    }

    /// The name every temporary copy of a peer's file starts with, so `removeTemporaryCopy` finds
    /// what `FileUrlDataController.heldPeerFileUrl` wrote. See CODE_AUDIT §9.16.
    static let temporaryCopyPrefix = "peer-"

    static func temporaryCopyName(of fileId: UUID) -> String {
        "\(temporaryCopyPrefix)\(fileId.uuidString)"
    }

    /// Removes the temporary copies of `fileIds`, listing the directory once for all of them. The
    /// copy of a generation in `keeping` stays.
    private static func removeTemporaryCopies(of fileIds: [UUID], keeping: [UUID: Int] = [:]) {
        guard !fileIds.isEmpty else { return }
        let prefixes = fileIds.map { fileId in
            let prefix = temporaryCopyName(of: fileId)
            return (prefix: prefix, kept: keeping[fileId].map { generation in "\(prefix)-\(generation)" })
        }
        let directory = URL.temporaryDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        for name in names {
            guard let match = prefixes.first(where: { name.hasPrefix($0.prefix) }) else { continue }
            if let kept = match.kept, name == kept || name.hasPrefix(kept + ".") { continue }
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
