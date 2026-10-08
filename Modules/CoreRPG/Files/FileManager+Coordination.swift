// @copyright André Trettin

import Foundation
import Synchronization

extension FileManager {

    func fileExists(coordinatingAccessAt fileURL: URL) async throws -> (exists: Bool, isDirectory: Bool) {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: fileURL) { cancellation in
            try Self.coordinate(cancellation, readingItemAt: fileURL) { url in
                var isDir: ObjCBool = false
                let coordinatedExists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir)
                return (coordinatedExists, isDir.boolValue)
            }
        }
    }
    
    func createDirectory(coordinatingAccessAt dirURL: URL, withIntermediateDirectories: Bool) async throws {
        try await Self.performCoordinatedFileAccess { cancellation in
            try Self.coordinate(cancellation, writingItemAt: dirURL, options: .forMerging) { url in
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            }
        }
    }
    
    /// Removes the file at `fileURL`. A folder is never removed and throws
    /// `DirectoryRemovalRefused`: every caller deletes one item's file, and a stored path that
    /// resolved to a module folder took every file of the module with it.
    /// See CODE_AUDIT_21 §5.1, §6.1.
    func removeFile(coordinatingAccessAt fileURL: URL) async throws {
        try await Self.performCoordinatedFileAccess { cancellation in
            try Self.coordinate(cancellation, writingItemAt: fileURL, options: .forDeleting) { url in
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue {
                    throw DirectoryRemovalRefused()
                }
                try FileManager.default.removeItem(at: url)
            }
        }
    }
    
    public func copyItem(coordinatingAccessFrom fromURL: URL, to toURL: URL) async throws {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: fromURL) { cancellation in
            try Self.coordinate(cancellation, readingItemAt: fromURL, readOptions: [], writingItemAt: toURL, writeOptions: .forReplacing) { readURL, writeURL in
                try FileManager.default.copyItem(at: readURL, to: writeURL)
            }
        }
    }

    func moveItem(coordinatingAccessFrom fromURL: URL, to toURL: URL) async throws {
        try await Self.performCoordinatedFileAccess { cancellation in
            try Self.coordinate(cancellation, writingItemAt: fromURL, writingItemAt: toURL) { readURL, writeURL in
                try FileManager.default.moveItem(at: readURL, to: writeURL)
            }
        }
    }

    func contentsOfDirectory(coordinatingAccessAt dirURL: URL) async throws -> [URL] {
        let keys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .isReadableKey, .ubiquitousItemIsDownloadingKey]
        return try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: dirURL) { cancellation in
            try Self.coordinate(cancellation, readingItemAt: dirURL) { url in
                try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            }
        }
    }
    
    /// The streamed content hash of the file at `url`. See CODE_AUDIT_19 §7.1.
    func contentHash(coordinatingAccessAt url: URL) async throws -> String {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: url) { cancellation in
            try Self.coordinate(cancellation, readingItemAt: url) { url in
                try FileUrl.contentHash(ofFileAt: url)
            }
        }
    }

    /// Opens the file at `url` for reading inside a coordinated read, so an iCloud file is
    /// downloaded first. The open handle stays readable after the coordination ends, which lets
    /// a caller copy a large file in blocks instead of loading it. See CODE_AUDIT_Folder §7.1.
    func fileHandle(coordinatingReadingAt url: URL) async throws -> FileHandle {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: url) { cancellation in
            try Self.coordinate(cancellation, readingItemAt: url) { url in
                try FileHandle(forReadingFrom: url)
            }
        }
    }

    /// Copies a file to `toURL` without reading it into memory, creating the parent folder and
    /// replacing a file already there. See CODE_AUDIT_19 §7.1.
    func copyReplacingItem(coordinatingAccessFrom fromURL: URL, to toURL: URL) async throws {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: fromURL) { cancellation in
            try Self.coordinate(cancellation, readingItemAt: fromURL, readOptions: [], writingItemAt: toURL, writeOptions: .forReplacing) { readURL, writeURL in
                // Replacing a file with itself would delete it. See CODE_AUDIT_20 §5.1.
                guard readURL.standardizedFileURL.resolvingSymlinksInPath() != writeURL.standardizedFileURL.resolvingSymlinksInPath() else { return }
                try FileManager.default.createDirectory(at: writeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: writeURL.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: writeURL)
                }
                try FileManager.default.copyItem(at: readURL, to: writeURL)
            }
        }
    }

    /// Copies a file to `toURL`, creating the parent folder, and throws `fileWriteFileExists`
    /// instead of replacing a file that is already there. A caller that picked `toURL` as a free
    /// name can retry with the next one, so two copies racing for one name never overwrite each
    /// other. See CODE_AUDIT_Folder §3.18.
    func copyItemWithoutReplacing(coordinatingAccessFrom fromURL: URL, to toURL: URL) async throws {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: fromURL) { cancellation in
            try Self.coordinate(cancellation, readingItemAt: fromURL, readOptions: [], writingItemAt: toURL, writeOptions: []) { readURL, writeURL in
                try FileManager.default.createDirectory(at: writeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: readURL, to: writeURL)
            }
        }
    }

    func contentsOfFile(coordinatingAccessAt url: URL) async throws -> Data {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: url) { cancellation in
            try Self.coordinate(cancellation, readingItemAt: url) { url in
                try Data(contentsOf: url)
            }
        }
    }

    public func download(coordinatingAccessAt url: URL) async throws {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: url) { cancellation in
            try Self.coordinate(cancellation, writingItemAt: url) { newUrl in
                try FileManager.default.startDownloadingUbiquitousItem(at: newUrl)
            }
        }
    }

    func write(_ data: Data, coordinatingAccessTo url: URL) async throws {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: url) { cancellation in
            try Self.coordinate(cancellation, writingItemAt: url) { url in
                try data.write(to: url)
            }
        }
    }
    
    func updateFile<T: Sendable>(coordinatingAccessTo url: URL, in block: @escaping @Sendable (URL) throws -> T) async throws -> T {
        try await Self.performCoordinatedFileAccess(mayWaitForDownloadOf: url) { cancellation in
            try Self.coordinate(cancellation, writingItemAt: url) { url in
                try block(url)
            }
        }
    }
    
    /// - Parameter url: The item whose coordination waits for an iCloud download when it is not
    ///   on this device: the one the operation reads, or writes in place. `nil` for an
    ///   operation that never waits for one (remove, move, create a folder).
    private static func performCoordinatedFileAccess<T: Sendable>(mayWaitForDownloadOf url: URL? = nil, _ operation: @escaping @Sendable (CoordinationCancellation) throws -> T) async throws -> T {
        // NSFileCoordinator is synchronous and can block while waiting on file presenters or
        // an iCloud download. Run it away from caller tasks so user-initiated work suspends
        // instead of blocking its thread — and cap how many of these blocking calls hold a
        // cooperative-pool thread at once, so a list of evicted iCloud files can never occupy
        // every thread and starve unrelated async work (LAN receive loops, sleeps, decoding).
        // See CODE_AUDIT_15 §3.1.
        //
        // An access that can wait for an iCloud download takes its slot from a smaller share, so
        // downloads that stall (offline, a slow iCloud) never hold every slot: a playlist of
        // evicted tracks used to queue every local import, delete and move behind it.
        // See CODE_AUDIT_21 §3.8.
        var slot = CoordinatedAccessLimiter.Slot.local
        if let url, await waitsForDownload(of: url) {
            slot = .download
        }
        try await CoordinatedAccessLimiter.shared.acquire(slot)
        // The blocking call runs on a dedicated `OperationQueue` thread, not a cooperative-pool
        // thread: waiting on an iCloud download used to pin up to 4 pool threads (most of the
        // pool on a 6-core device). The limiter above keeps this queue from building a backlog.
        // See CODE_AUDIT_18 §7.3.
        //
        // Cancelling the calling task cancels the coordinator the operation is blocked in, so a
        // read waiting on an iCloud download returns (and frees its limiter slot) instead of
        // holding it until the download finishes. See CODE_AUDIT_Folder §3.13.
        let cancellation = CoordinationCancellation()
        do {
            let result = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                    coordinationQueue.addOperation {
                        continuation.resume(with: Result { try operation(cancellation) })
                    }
                }
            } onCancel: {
                cancellation.cancel()
            }
            await CoordinatedAccessLimiter.shared.release(slot)
            return result
        } catch {
            await CoordinatedAccessLimiter.shared.release(slot)
            // A cancelled coordinator reports `NSUserCancelledError`; surface it as the
            // cancellation it is.
            if cancellation.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Whether coordinating access to `url` can block on an iCloud download: an iCloud item whose
    /// current version is not on this device. `@concurrent`: the resource values are read off
    /// the caller's actor. A file that does not exist yet, or is outside iCloud, never waits.
    @concurrent
    private static func waitsForDownload(of url: URL) async -> Bool {
        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else { return false }
        return values.ubiquitousItemDownloadingStatus != .current
    }

    private static let coordinationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "FileManager.coordination"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = CoordinatedAccessLimiter.maximumConcurrentAccesses
        return queue
    }()

    private static func execute<T>(_ block: (URL) throws -> T, onSecurityScopedResource url: URL) throws -> T {
        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        return try block(url)
    }
    
    private static func coordinate<T>(_ cancellation: CoordinationCancellation, readingItemAt url: URL, options: NSFileCoordinator.ReadingOptions = [], with block: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = cancellation.makeCoordinator()
        coordinator.coordinate(readingItemAt: url, options: options, error: &coordinatorError) { url in
            result = Result { try execute(block, onSecurityScopedResource: url) }
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else {
            // `NSFileCoordinator` reliably invokes the block (setting `result`) or sets
            // `coordinatorError` on every real-world path — this is a last-resort guard
            // against a future contract violation degrading to a caught error instead of
            // a crash. See CODE_AUDIT §5.3.
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }
    
    private static func coordinate<T>(_ cancellation: CoordinationCancellation, writingItemAt url: URL, options: NSFileCoordinator.WritingOptions = [], with block: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = cancellation.makeCoordinator()
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinatorError) { url in
            result = Result { try execute(block, onSecurityScopedResource: url) }
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else {
            // `NSFileCoordinator` reliably invokes the block (setting `result`) or sets
            // `coordinatorError` on every real-world path — this is a last-resort guard
            // against a future contract violation degrading to a caught error instead of
            // a crash. See CODE_AUDIT §5.3.
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }
    
    private static func coordinate<T>(_ cancellation: CoordinationCancellation, readingItemAt readURL: URL, readOptions: NSFileCoordinator.ReadingOptions = [], writingItemAt writeURL: URL, writeOptions: NSFileCoordinator.WritingOptions = [], with block: (_ readURL: URL, _ writeURL: URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = cancellation.makeCoordinator()
        coordinator.coordinate(readingItemAt: readURL, options: readOptions, writingItemAt: writeURL, options: writeOptions, error: &coordinatorError) { (read: URL, write: URL) in
            result = Result {
                try execute(onSecurityScopedResource: read, and: write, with: block)
            }
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else {
            // `NSFileCoordinator` reliably invokes the block (setting `result`) or sets
            // `coordinatorError` on every real-world path — this is a last-resort guard
            // against a future contract violation degrading to a caught error instead of
            // a crash. See CODE_AUDIT §5.3.
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }

    private static func coordinate<T>(_ cancellation: CoordinationCancellation, writingItemAt sourceURL: URL, writingItemAt destinationURL: URL, with block: (_ sourceURL: URL, _ destinationURL: URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = cancellation.makeCoordinator()
        coordinator.coordinate(writingItemAt: sourceURL, options: .forMoving, writingItemAt: destinationURL, options: .forReplacing, error: &coordinatorError) { (read: URL, write: URL) in
            result = Result {
                try execute(onSecurityScopedResource: read, and: write, with: block)
            }
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else {
            // `NSFileCoordinator` reliably invokes the block (setting `result`) or sets
            // `coordinatorError` on every real-world path — this is a last-resort guard
            // against a future contract violation degrading to a caught error instead of
            // a crash. See CODE_AUDIT §5.3.
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }

    private static func execute<T>(onSecurityScopedResource firstURL: URL, and secondURL: URL, with block: (_ firstURL: URL, _ secondURL: URL) throws -> T) throws -> T {
        let firstScope = firstURL.startSecurityScopedAccess()
        let secondScope = secondURL.startSecurityScopedAccess()
        defer {
            firstScope.stop()
            secondScope.stop()
        }
        return try block(firstURL, secondURL)
    }
}

/// Thrown by `FileManager.removeFile(coordinatingAccessAt:)` when the target is a folder.
struct DirectoryRemovalRefused: Error {}

/// Lets a task's cancellation reach the `NSFileCoordinator` a coordinated operation is blocked
/// in. A coordinator created after cancellation is cancelled straight away, so the operation
/// returns `NSUserCancelledError` instead of starting. See CODE_AUDIT_Folder §3.13.
final class CoordinationCancellation: Sendable {
    /// `NSFileCoordinator.cancel()` may be called from any thread, but the class is not
    /// annotated `Sendable`; this box carries it into the lock and across threads.
    private final class CoordinatorBox: @unchecked Sendable {
        let coordinator = NSFileCoordinator(filePresenter: nil)
    }

    private struct State: Sendable {
        var box: CoordinatorBox?
        var isCancelled = false
    }

    private let state = Mutex(State())

    var isCancelled: Bool {
        state.withLock { $0.isCancelled }
    }

    func makeCoordinator() -> NSFileCoordinator {
        let box = CoordinatorBox()
        let isCancelled = state.withLock { state in
            state.box = box
            return state.isCancelled
        }
        if isCancelled {
            box.coordinator.cancel()
        }
        return box.coordinator
    }

    func cancel() {
        let box = state.withLock { state in
            state.isCancelled = true
            return state.box
        }
        box?.coordinator.cancel()
    }
}

/// Bounds the number of blocking `NSFileCoordinator` calls running at once; further callers
/// wait (cancellably) in FIFO order without occupying a thread.
///
/// Accesses that can wait for an iCloud download (`Slot.download`) may hold all slots but one.
/// The last one is kept for accesses that cannot (`Slot.local`), so a stalled iCloud never
/// stops local file work; nothing cancels those waits, and several callers are tasks nobody
/// cancels. See CODE_AUDIT_21 §3.8.
actor CoordinatedAccessLimiter {
    enum Slot: Sendable {
        /// The access can block until iCloud has delivered the file.
        case download
        /// The access only waits for other coordinated accesses.
        case local
    }

    /// At least two, so one slot can be kept for local accesses. The blocking calls run on
    /// their own `OperationQueue`, not on cooperative-pool threads.
    static let maximumConcurrentAccesses = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 1))
    static let shared = CoordinatedAccessLimiter(limit: maximumConcurrentAccesses)

    private let limit: Int
    private let downloadLimit: Int
    private var running = 0
    private var runningDownloads = 0
    private var waiters: [(id: UUID, slot: Slot, continuation: CheckedContinuation<Void, any Error>)] = []

    init(limit: Int) {
        self.limit = max(1, limit)
        self.downloadLimit = max(1, limit - 1)
    }

    /// Accesses waiting for a slot.
    var waiterCount: Int {
        waiters.count
    }

    func acquire(_ slot: Slot) async throws {
        try Task.checkCancellation()
        // Every waiter that could run was started by the last `release`, so a newcomer that
        // can run overtakes nobody of its own kind.
        if canRun(slot) {
            start(slot)
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append((id, slot, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func release(_ slot: Slot) {
        running -= 1
        if slot == .download {
            runningDownloads -= 1
        }
        // In arrival order, skipping download waiters while their share is used up.
        while let index = waiters.firstIndex(where: { canRun($0.slot) }) {
            let waiter = waiters.remove(at: index)
            start(waiter.slot)
            waiter.continuation.resume()
        }
    }

    private func canRun(_ slot: Slot) -> Bool {
        guard running < limit else { return false }
        return slot == .local || runningDownloads < downloadLimit
    }

    private func start(_ slot: Slot) {
        running += 1
        if slot == .download {
            runningDownloads += 1
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
