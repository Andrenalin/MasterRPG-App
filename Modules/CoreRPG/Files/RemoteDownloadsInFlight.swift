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

    private struct Entry {
        let id = UUID()
        var task: Task<Void, any Error>?
        var waiters = 0
    }

    private let entries = Mutex<[String: Entry]>([:])

    /// Runs `download` unless one for `cachePath` is running already, and waits for whichever
    /// it is. A caller that is cancelled stops waiting; the download goes on for the others and
    /// is cancelled when the last of them has left. See CODE_AUDIT_23 §3.2.
    func run(cachePath: String, _ download: @escaping @Sendable () async throws -> Void) async throws {
        // The task is created under the lock, so it cannot remove itself before it is stored.
        let (task, entryId) = entries.withLock { entries -> (Task<Void, any Error>, UUID) in
            if var running = entries[cachePath], let task = running.task {
                running.waiters += 1
                entries[cachePath] = running
                return (task, running.id)
            }
            var entry = Entry()
            let entryId = entry.id
            let task = Task {
                defer {
                    // A cancelled download may already have been replaced by a newer one.
                    self.entries.withLock { entries in
                        if entries[cachePath]?.id == entryId { entries[cachePath] = nil }
                    }
                }
                try await download()
            }
            entry.task = task
            entry.waiters = 1
            entries[cachePath] = entry
            return (task, entryId)
        }
        defer { leave(cachePath: cachePath, entryId: entryId) }
        // `task.value` does not stop waiting when the caller is cancelled, so the wait is a
        // continuation that either the download or the cancellation resumes, whichever is first.
        let wait = CancellableWait()
        Task {
            do {
                try await task.value
                wait.finish(.success(()))
            } catch {
                wait.finish(.failure(error))
            }
        }
        try await withTaskCancellationHandler {
            try await wait.wait()
        } onCancel: {
            wait.finish(.failure(CancellationError()))
        }
        try Task.checkCancellation()
    }

    /// Drops one waiter, and cancels the download, which nobody waits for any more.
    private func leave(cachePath: String, entryId: UUID) {
        let abandoned: Task<Void, any Error>? = entries.withLock { entries in
            guard var entry = entries[cachePath], entry.id == entryId else { return nil }
            entry.waiters -= 1
            guard entry.waiters <= 0 else {
                entries[cachePath] = entry
                return nil
            }
            entries[cachePath] = nil
            return entry.task
        }
        abandoned?.cancel()
    }
}

/// A one-shot wait that `finish` ends from any thread, also when it comes before `wait`.
private final class CancellableWait: Sendable {
    private enum State {
        case idle
        case waiting(CheckedContinuation<Void, any Error>)
        case finished(Result<Void, any Error>)
    }

    private let state = Mutex<State>(.idle)

    func wait() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let finished: Result<Void, any Error>? = state.withLock { state in
                if case let .finished(result) = state { return result }
                state = .waiting(continuation)
                return nil
            }
            if let finished { continuation.resume(with: finished) }
        }
    }

    func finish(_ result: Result<Void, any Error>) {
        let continuation: CheckedContinuation<Void, any Error>? = state.withLock { state in
            switch state {
            case .finished:
                return nil
            case let .waiting(continuation):
                state = .finished(result)
                return continuation
            case .idle:
                state = .finished(result)
                return nil
            }
        }
        continuation?.resume(with: result)
    }
}
