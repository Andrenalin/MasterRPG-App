// @copyright André Trettin

import Foundation
import Testing
import UniformTypeIdentifiers

@testable import CoreRPG

/// CODE_AUDIT_26 §10.8: the history timestamp rules as pure functions and `ensureRemoteCache`
/// with an injected downloader.
@Suite("Persistent history timestamp rules")
struct PersistentHistoryTimestampTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Without any actor position, cleanup stops at the retention floor")
    func noPositionsUsesFloor() {
        let result = PersistentHistoryTimestamps.safeCleanupTimestamp(actorTimestamps: [], now: now)

        #expect(result == now.addingTimeInterval(-PersistentHistoryTimestamps.retention))
    }

    @Test("A recent position cannot move the cleanup past the retention floor")
    func recentPositionIsCappedAtFloor() {
        let result = PersistentHistoryTimestamps.safeCleanupTimestamp(
            actorTimestamps: [now.addingTimeInterval(-60)],
            now: now
        )

        #expect(result == now.addingTimeInterval(-PersistentHistoryTimestamps.retention))
    }

    @Test("An old position holds the cleanup back to the slowest actor")
    func slowestActorWins() {
        let slowest = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let result = PersistentHistoryTimestamps.safeCleanupTimestamp(
            actorTimestamps: [now.addingTimeInterval(-10 * 24 * 60 * 60), slowest, now.addingTimeInterval(-60)],
            now: now
        )

        #expect(result == slowest)
    }

    @Test("A position is never rewound")
    func positionNeverRewinds() {
        let current = now
        #expect(PersistentHistoryTimestamps.advanced(current: current, to: now.addingTimeInterval(-10)) == nil)
        #expect(PersistentHistoryTimestamps.advanced(current: current, to: current) == nil)
    }

    @Test("A lagging or unset position advances")
    func laggingPositionAdvances() {
        let target = now
        #expect(PersistentHistoryTimestamps.advanced(current: target.addingTimeInterval(-1), to: target) == target)
        #expect(PersistentHistoryTimestamps.advanced(current: nil, to: target) == target)
    }
}

@Suite("ensureRemoteCache with an injected downloader")
struct EnsureRemoteCacheTests {
    private func makeController(module: String, downloader: @escaping @Sendable (URL) async throws -> URL) async -> FileUrlDataController {
        await FileUrlDataController(
            moduleFolder: module,
            fileTypes: [.data],
            filenameExtension: "test",
            remoteFileDownloader: downloader
        )
    }

    private func remoteFileUrl(module: String) throws -> FileUrl {
        FileUrl(
            fileId: UUID(),
            url: try #require(URL(string: "https://example.com/content/\(UUID().uuidString).test")),
            location: .url,
            module: module,
            relativeUrl: nil
        )
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("test")
        try data.write(to: url)
        return url
    }

    @Test("Readers that ask at once share one download")
    func concurrentReadersShareOneDownload() async throws {
        let module = uniqueModuleName()
        let counter = DownloadCounter()
        let payload = Data("shared".utf8)
        let sut = await makeController(module: module) { _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(150))
            let url = URL.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("test")
            try payload.write(to: url)
            return url
        }
        let fileUrl = try remoteFileUrl(module: module)

        let results = try await withThrowingTaskGroup(of: URL?.self) { group in
            for _ in 0..<4 {
                group.addTask { try await sut.ensureRemoteCache(for: fileUrl) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(await counter.count == 1)
        #expect(Set(results.compactMap { $0 }).count == 1)
        try? FileManager.default.removeItem(at: sut.remoteCacheURL(for: fileUrl))
    }

    @Test("A failed download leaves no cache file and the next read downloads again")
    func failedDownloadCanBeRetried() async throws {
        let module = uniqueModuleName()
        let counter = DownloadCounter()
        let sourceUrl = try temporaryFile(Data("retry".utf8))
        let sut = await makeController(module: module) { _ in
            let attempt = await counter.increment()
            if attempt == 1 { throw URLError(.notConnectedToInternet) }
            return sourceUrl
        }
        let fileUrl = try remoteFileUrl(module: module)

        await #expect(throws: URLError.self) {
            _ = try await sut.ensureRemoteCache(for: fileUrl)
        }
        #expect(!FileManager.default.fileExists(atPath: sut.remoteCacheURL(for: fileUrl).path(percentEncoded: false)))

        let cached = try await sut.ensureRemoteCache(for: fileUrl)

        #expect(cached == sut.remoteCacheURL(for: fileUrl))
        #expect(try Data(contentsOf: sut.remoteCacheURL(for: fileUrl)) == Data("retry".utf8))
        try? FileManager.default.removeItem(at: sut.remoteCacheURL(for: fileUrl))
    }

    @Test("A download over the size limit is refused, cached nowhere and removed from tmp")
    func oversizedDownloadIsRefused() async throws {
        let module = uniqueModuleName()
        let oversized = URL.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("test")
        #expect(FileManager.default.createFile(atPath: oversized.path(percentEncoded: false), contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        // A sparse file: the size is what counts, no bytes are written.
        try handle.truncate(atOffset: UInt64(ByteLimits.maximumSourceFileBytes) + 1)
        try handle.close()
        let sut = await makeController(module: module) { _ in oversized }
        let fileUrl = try remoteFileUrl(module: module)

        await #expect(throws: URLError.self) {
            _ = try await sut.ensureRemoteCache(for: fileUrl)
        }

        #expect(!FileManager.default.fileExists(atPath: sut.remoteCacheURL(for: fileUrl).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: oversized.path(percentEncoded: false)))
    }

    @Test("A file that is not a remote URL is not downloaded")
    func nonRemoteFileIsSkipped() async throws {
        let module = uniqueModuleName()
        let counter = DownloadCounter()
        let sut = await makeController(module: module) { _ in
            await counter.increment()
            throw URLError(.badURL)
        }
        let local = FileUrl(
            fileId: UUID(),
            url: URL.temporaryDirectory.appending(path: "local.test"),
            location: .local,
            module: module,
            relativeUrl: nil
        )

        let result = try await sut.ensureRemoteCache(for: local)

        #expect(result == nil)
        #expect(await counter.count == 0)
    }
}

private actor DownloadCounter {
    private(set) var count = 0

    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }
}

private func uniqueModuleName() -> String {
    "RemoteCacheTests-\(UUID().uuidString)"
}
