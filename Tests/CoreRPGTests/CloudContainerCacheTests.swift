// @copyright André Trettin

import Foundation
import Synchronization
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §5.11: a missing container is only believed for a while when an iCloud identity exists.
@Suite("CloudContainerCache")
struct CloudContainerCacheTests {
    private final class Clock: Sendable {
        private let offset = Mutex(Duration.zero)
        private let start = ContinuousClock.now
        var now: ContinuousClock.Instant { start + offset.withLock { $0 } }
        func advance(_ duration: Duration) { offset.withLock { $0 += duration } }
    }

    private final class Probe: Sendable {
        let calls = Mutex(0)
        let result = Mutex<URL?>(nil)
    }

    private func makeCache(hasIdentity: Bool, clock: Clock, probe: Probe) -> CloudContainerCache {
        CloudContainerCache(
            hasIdentity: { hasIdentity },
            resolveContainer: {
                probe.calls.withLock { $0 += 1 }
                return probe.result.withLock { $0 }
            },
            retryInterval: .seconds(5),
            now: { clock.now }
        )
    }

    @Test("A container that appears after the first lookup is found once the retry interval passed")
    func missingContainerIsRetried() {
        let clock = Clock()
        let probe = Probe()
        let cache = makeCache(hasIdentity: true, clock: clock, probe: probe)

        #expect(cache.url == nil)
        #expect(cache.url == nil)
        #expect(probe.calls.withLock { $0 } == 1, "inside the interval the miss is reused")

        let container = URL(filePath: "/tmp/container")
        probe.result.withLock { $0 = container }
        clock.advance(.seconds(6))

        #expect(cache.url == container)
        #expect(probe.calls.withLock { $0 } == 2)
        clock.advance(.seconds(60))
        #expect(cache.url == container)
        #expect(probe.calls.withLock { $0 } == 2, "a found container is cached for good")
    }

    @Test("Without an iCloud identity the nil result stays cached, a sign-in invalidates it")
    func noIdentityIsCached() {
        let clock = Clock()
        let probe = Probe()
        let cache = makeCache(hasIdentity: false, clock: clock, probe: probe)

        #expect(cache.url == nil)
        clock.advance(.seconds(600))
        #expect(cache.url == nil)
        #expect(probe.calls.withLock { $0 } == 0, "no identity: the system call is not made at all")
    }

    @Test("invalidate() forgets a stored container")
    func invalidateDropsTheCache() {
        let clock = Clock()
        let probe = Probe()
        let first = URL(filePath: "/tmp/first")
        probe.result.withLock { $0 = first }
        let cache = makeCache(hasIdentity: true, clock: clock, probe: probe)
        #expect(cache.url == first)

        let second = URL(filePath: "/tmp/second")
        probe.result.withLock { $0 = second }
        cache.invalidate()
        #expect(cache.url == second)
    }
}
