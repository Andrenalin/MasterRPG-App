// @copyright André Trettin

import Foundation
import Synchronization

/// The downloads of remote files into the cache that are running, by the cache file they fill.
///
/// Several readers ask for one uncached remote file together (the list thumbnail, the detail
/// view, a game reveal). Each used to download it, up to 256 MiB apiece, and all but one copy
/// was thrown away. A second request for the same cache file now waits for the first.
/// See CODE_AUDIT_21 §7.5.
final class RemoteDownloadsInFlight: Sendable {
    static let shared = RemoteDownloadsInFlight()

    private let tasks = Mutex<[String: Task<Void, any Error>]>([:])

    /// Runs `download` unless one for `cachePath` is running already, and waits for whichever
    /// it is. A caller that is cancelled stops waiting; the download goes on for the others.
    func run(cachePath: String, _ download: @escaping @Sendable () async throws -> Void) async throws {
        // The task is created under the lock, so it cannot remove itself before it is stored.
        let task = tasks.withLock { tasks in
            if let running = tasks[cachePath] { return running }
            let task = Task {
                defer { self.tasks.withLock { $0[cachePath] = nil } }
                try await download()
            }
            tasks[cachePath] = task
            return task
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {}
        try Task.checkCancellation()
    }
}
