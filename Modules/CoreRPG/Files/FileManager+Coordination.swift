// @copyright André Trettin

import Foundation

extension FileManager {

    func fileExists(coordinatingAccessAt fileURL: URL) async throws -> (exists: Bool, isDirectory: Bool) {
        try await Self.performCoordinatedFileAccess {
            try Self.coordinate(readingItemAt: fileURL) { url in
                var isDir: ObjCBool = false
                let coordinatedExists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return (coordinatedExists, isDir.boolValue)
            }
        }
    }
    
    func createDirectory(coordinatingAccessAt dirURL: URL, withIntermediateDirectories: Bool) async throws {
        try await Self.performCoordinatedFileAccess {
            try Self.coordinate(writingItemAt: dirURL, options: .forMerging) { url in
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
            }
        }
    }
    
    func removeItem(coordinatingAccessAt dirURL: URL) async throws {
        try await Self.performCoordinatedFileAccess {
            try Self.coordinate(writingItemAt: dirURL, options: .forDeleting) { url in
                try FileManager.default.removeItem(at: url)
            }
        }
    }
    
    func copyItem(coordinatingAccessFrom fromURL: URL, to toURL: URL) async throws {
        try await Self.performCoordinatedFileAccess {
            try Self.coordinate(readingItemAt: fromURL, readOptions: [], writingItemAt: toURL, writeOptions: .forReplacing) { readURL, writeURL in
                try FileManager.default.copyItem(at: readURL, to: writeURL)
            }
        }
    }

    func moveItem(coordinatingAccessFrom fromURL: URL, to toURL: URL) async throws {
        try await Self.performCoordinatedFileAccess {
            try Self.coordinate(writingItemAt: fromURL, writingItemAt: toURL) { readURL, writeURL in
                try FileManager.default.moveItem(at: readURL, to: writeURL)
            }
        }
    }

    func contentsOfDirectory(coordinatingAccessAt dirURL: URL) async throws -> [URL] {
        let keys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .isReadableKey, .ubiquitousItemIsDownloadingKey]
        return try await Self.performCoordinatedFileAccess {
            try Self.coordinate(readingItemAt: dirURL) { url in
                try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            }
        }
    }
    
    func contentsOfFile(coordinatingAccessAt url: URL) async throws -> Data {
        try await Self.performCoordinatedFileAccess {
            try Self.coordinate(readingItemAt: url) { url in
                try Data(contentsOf: url)
            }
        }
    }

    func download(coordinatingAccessAt url: URL) async throws {
        try await Self.performCoordinatedFileAccess {
            try Self.coordinate(writingItemAt: url) { newUrl in
                try FileManager.default.startDownloadingUbiquitousItem(at: newUrl)
            }
        }
    }

    func write(_ data: Data, coordinatingAccessTo url: URL) async throws {
        try await Self.performCoordinatedFileAccess {
            try Self.coordinate(writingItemAt: url) { url in
                try data.write(to: url)
            }
        }
    }
    
    func updateFile<T: Sendable>(coordinatingAccessTo url: URL, in block: @escaping @Sendable (URL) throws -> T) async throws -> T {
        try await Self.performCoordinatedFileAccess {
            try Self.coordinate(writingItemAt: url) { url in
                try block(url)
            }
        }
    }
    
    private static func performCoordinatedFileAccess<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        // NSFileCoordinator is synchronous and can block while waiting on file presenters or
        // an iCloud download. Run it away from caller tasks so user-initiated work suspends
        // instead of blocking its thread — and cap how many of these blocking calls hold a
        // cooperative-pool thread at once, so a list of evicted iCloud files can never occupy
        // every thread and starve unrelated async work (LAN receive loops, sleeps, decoding).
        // See CODE_AUDIT_15 §3.1.
        try await CoordinatedAccessLimiter.shared.acquire()
        let task = Task.detached(priority: .utility) {
            try operation()
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            await CoordinatedAccessLimiter.shared.release()
            return result
        } catch {
            await CoordinatedAccessLimiter.shared.release()
            throw error
        }
    }

    private static func execute<T>(_ block: (URL) throws -> T, onSecurityScopedResource url: URL) throws -> T {
        let securityScope = url.startSecurityScopedAccess()
        defer { securityScope.stop() }
        return try block(url)
    }
    
    private static func coordinate<T>(readingItemAt url: URL, options: NSFileCoordinator.ReadingOptions = [], with block: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
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
    
    private static func coordinate<T>(writingItemAt url: URL, options: NSFileCoordinator.WritingOptions = [], with block: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
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
    
    private static func coordinate<T>(readingItemAt readURL: URL, readOptions: NSFileCoordinator.ReadingOptions = [], writingItemAt writeURL: URL, writeOptions: NSFileCoordinator.WritingOptions = [], with block: (_ readURL: URL, _ writeURL: URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
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

    private static func coordinate<T>(writingItemAt sourceURL: URL, writingItemAt destinationURL: URL, with block: (_ sourceURL: URL, _ destinationURL: URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
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

/// Bounds the number of blocking `NSFileCoordinator` calls running at once; further callers
/// wait (cancellably) in FIFO order without occupying a thread. Always leaves at least one
/// cooperative-pool thread free.
private actor CoordinatedAccessLimiter {
    static let shared = CoordinatedAccessLimiter(limit: max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1)))

    private let limit: Int
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async throws {
        try Task.checkCancellation()
        if running < limit {
            running += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            // The slot is handed over directly, `running` stays unchanged.
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
