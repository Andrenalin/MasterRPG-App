// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
@Suite("Resource cache")
struct ResourceCacheTests {
    @Test("A cancelled joiner does not receive the in-flight result")
    func cancelledJoinerPropagatesCancellation() async throws {
        // Given: a resource file the primary caller will start loading.
        let url = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let key = "joiner-cancellation-\(UUID().uuidString)"

        // Both tasks are only enqueued here, not run yet — neither starts
        // until this test function itself suspends. `load(key:from:)` sets
        // `inFlightRequests[key]` synchronously before its first suspension
        // (crossing to the detached read task), so as long as the primary
        // is enqueued first, it reaches that point before the joiner's
        // `load` call runs — no arbitrary sleep needed, and a fixed sleep
        // here would risk letting the (near-instant) read finish first,
        // making the joiner hit the cache instead of the in-flight branch.
        let primary = Task {
            try await ResourceCache.shared.load(key: key, from: url)
        }

        // When: a second caller joins the same in-flight request and is
        // cancelled before it resolves.
        let joiner = Task {
            try await ResourceCache.shared.load(key: key, from: url)
        }
        joiner.cancel()

        // Then: the cancelled joiner surfaces its own cancellation instead
        // of quietly returning the primary's successful result...
        await #expect(throws: CancellationError.self) {
            try await joiner.value
        }

        // ...while the primary caller (and the cache) are unaffected: the
        // result is correct, and a follow-up load now hits the cache.
        let primaryResult = try await primary.value
        #expect(primaryResult == Data("hello".utf8))
        let cachedResult = try await ResourceCache.shared.load(key: key, from: url)
        #expect(cachedResult == Data("hello".utf8))

        ResourceCache.shared.clear(key: key)
    }

    private func makeTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        return url
    }
}
