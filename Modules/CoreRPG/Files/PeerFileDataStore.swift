// @copyright André Trettin

import Combine
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import os.log
import Synchronization

/// Bytes game peers sent for files not downloaded from iCloud on this device, by file id.
/// Shared by the copies of one module's `FileUrlDataController`.
final class PeerFileDataStore: Sendable {
    private let entries = Mutex<[UUID: Data]>([:])

    func data(for fileId: UUID) -> Data? {
        entries.withLock { $0[fileId] }
    }

    func hold(_ data: Data, for fileId: UUID) {
        let replaced = entries.withLock { entries -> Bool in
            defer { entries[fileId] = data }
            return entries[fileId] != nil && entries[fileId] != data
        }
        if replaced { Self.removeTemporaryCopy(of: fileId) }
    }

    func remove(_ fileId: UUID) {
        let removed = entries.withLock { $0.removeValue(forKey: fileId) != nil }
        if removed { Self.removeTemporaryCopy(of: fileId) }
    }

    private static func removeTemporaryCopy(of fileId: UUID) {
        let prefix = "peer-\(fileId.uuidString)"
        let directory = URL.temporaryDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
