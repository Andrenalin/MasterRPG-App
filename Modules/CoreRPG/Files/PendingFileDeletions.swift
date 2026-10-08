// @copyright André Trettin

import Foundation
import Synchronization

/// The file deletions that were announced or started and have not finished, by the canonical
/// path of the stored file.
///
/// Deleting an item removes it from memory at once and its file later, in a detached task behind
/// the file-coordination limiter. In between the file is unreferenced but still on disk, so an
/// import of the same content found it, chose to reuse it, and the queued deletion then removed
/// it under the imported item. Whoever is about to reuse or write a stored file waits here for
/// the deletion of that path first. Deletions of one path run in the order they were announced.
/// The store is process-wide: paths are unique across modules. See CODE_AUDIT_21 §3.6.
public final class PendingFileDeletions: Sendable {
    static let shared = PendingFileDeletions()

    /// A deletion that was announced and has not been decided yet: `run` starts it, `withdraw`
    /// gives it up (the file stays). Waiters are held until one of the two; an announcement
    /// that is dropped counts as withdrawn. Public only as a value the file controller's public
    /// `delete` passes through.
    public final class Announcement: Sendable {
        private let continuation: AsyncStream<@Sendable () async -> Void>.Continuation

        fileprivate init(continuation: AsyncStream<@Sendable () async -> Void>.Continuation) {
            self.continuation = continuation
        }

        deinit {
            continuation.finish()
        }

        func run(_ deletion: @escaping @Sendable () async -> Void) {
            continuation.yield(deletion)
            continuation.finish()
        }

        func withdraw() {
            continuation.finish()
        }
    }

    private struct Entry {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let entries = Mutex<[String: Entry]>([:])

    /// Marks the file at `path` as about to be deleted. Called in the same step that takes the
    /// file's item out of memory, so nobody can see the file unreferenced without also seeing
    /// its deletion.
    func announce(at path: String) -> Announcement {
        let (deletions, continuation) = AsyncStream<@Sendable () async -> Void>.makeStream()
        let id = UUID()
        // The task is created under the lock, so it cannot reach `finish` before it is stored.
        entries.withLock { entries in
            let previous = entries[path]?.task
            let task = Task { @concurrent in
                await previous?.value
                for await deletion in deletions {
                    await deletion()
                }
                self.finish(id: id, at: path)
            }
            entries[path] = Entry(id: id, task: task)
        }
        return Announcement(continuation: continuation)
    }

    /// Starts `deletion` off the caller's actor and keeps it findable under `path` until it has
    /// finished. Without a path (a reference the app stores no file for) it only runs.
    func start(at path: String?, _ deletion: @escaping @Sendable () async -> Void) {
        guard let path else {
            Task { @concurrent in await deletion() }
            return
        }
        announce(at: path).run(deletion)
    }

    /// Returns once no deletion of the file at `path` is announced or running. A deletion
    /// announced while waiting is waited for as well.
    func waitUntilFinished(at path: String) async {
        while let task = entries.withLock({ $0[path]?.task }) {
            await task.value
        }
    }

    private func finish(id: UUID, at path: String) {
        entries.withLock { entries in
            if entries[path]?.id == id {
                entries[path] = nil
            }
        }
    }
}
