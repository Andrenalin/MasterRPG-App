// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §6.2: the start/stop balance of security-scoped access and the
/// cancellation rules of the wrappers. A url inside the app container needs no scope, so the
/// start answers `false` and the stop must not be sent.
@Suite("Security-scoped access")
struct SecurityScopedAccessTests {
    private struct Failure: Error {}

    private static func temporaryFile() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "Scoped-\(UUID().uuidString).txt")
        try Data("content".utf8).write(to: url)
        return url
    }

    @Test("Stopping an access that was never started is harmless, also twice")
    func stopWithoutStart() throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let access = url.startSecurityScopedAccess()
        access.stop()
        access.stop()

        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test("The work receives the url and its result is returned")
    func synchronousWorkResult() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await url.withSecurityScopedAccess { scoped in
            try String(contentsOf: scoped, encoding: .utf8)
        }

        #expect(text == "content")
    }

    @Test("The async work receives the url and its result is returned")
    func asynchronousWorkResult() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let size = try await url.withSecurityScopedAccess { scoped in
            await Task.yield()
            return try Data(contentsOf: scoped).count
        }

        #expect(size == 7)
    }

    @Test("An error of the work is passed on and the scope is ended")
    func errorIsPassedOn() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: Failure.self) {
            try await url.withSecurityScopedAccess { _ -> Int in throw Failure() }
        }
        await #expect(throws: Failure.self) {
            try await url.withSecurityScopedAccess { _ async throws -> Int in throw Failure() }
        }
        // The next access still works: nothing was left unbalanced.
        let text = try await url.withSecurityScopedAccess { try String(contentsOf: $0, encoding: .utf8) }
        #expect(text == "content")
    }

    @Test("A task cancelled before the work starts never runs it")
    func cancelledBeforeTheWork() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let ran = Counter()

        let task = Task {
            // Not cancelled yet when it is created, so wait until it is.
            while !Task.isCancelled { await Task.yield() }
            return try await url.withSecurityScopedAccess { _ -> Int in ran.increment(); return 1 }
        }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ran.value == 0)
    }

    @Test("Nested accesses to one url are independent")
    func nestedAccess() async throws {
        let url = try Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await url.withSecurityScopedAccess { outer in
            let inner = outer.startSecurityScopedAccess()
            defer { inner.stop() }
            return try String(contentsOf: outer, encoding: .utf8)
        }

        #expect(text == "content")
    }

    @Test("The default-priority and off-executor helpers return their result and honour cancellation")
    func executorHelpers() async throws {
        let value = await runAtDefaultPriority { 42 }
        #expect(value == 42)
        let offExecutor = try await runOffCallerExecutor { 7 }
        #expect(offExecutor == 7)

        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await runOffCallerExecutor { 1 }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
#endif
