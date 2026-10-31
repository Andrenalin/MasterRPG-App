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
