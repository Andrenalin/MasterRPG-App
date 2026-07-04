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
        // NSFileCoordinator is synchronous and can block while waiting on file presenters.
        // Run it away from caller tasks so user-initiated work suspends instead of blocking its thread.
        try await Task.detached(priority: .utility) {
            try operation()
        }.value
    }

    private static func execute<T>(_ block: (URL) throws -> T, onSecurityScopedResource url: URL) throws -> T {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        return try block(url)
    }
    
    private static func coordinate<T>(readingItemAt url: URL, options: NSFileCoordinator.ReadingOptions = [], with block: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: options, error: &coordinatorError) { url in
            result = Result { try execute(block, onSecurityScopedResource: url) }
        }
        guard coordinatorError == nil else { throw coordinatorError! }
        return try result!.get()
    }
    
    private static func coordinate<T>(writingItemAt url: URL, options: NSFileCoordinator.WritingOptions = [], with block: (URL) throws -> T) throws -> T {
        var coordinatorError: NSError?
        var result: Result<T, Swift.Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinatorError) { url in
            result = Result { try execute(block, onSecurityScopedResource: url) }
        }
        guard coordinatorError == nil else { throw coordinatorError! }
        return try result!.get()
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
        guard coordinatorError == nil else { throw coordinatorError! }
        return try result!.get()
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
        guard coordinatorError == nil else { throw coordinatorError! }
        return try result!.get()
    }

    private static func execute<T>(onSecurityScopedResource firstURL: URL, and secondURL: URL, with block: (_ firstURL: URL, _ secondURL: URL) throws -> T) throws -> T {
        _ = firstURL.startAccessingSecurityScopedResource()
        _ = secondURL.startAccessingSecurityScopedResource()
        defer {
            firstURL.stopAccessingSecurityScopedResource()
            secondURL.stopAccessingSecurityScopedResource()
        }
        return try block(firstURL, secondURL)
    }
}
