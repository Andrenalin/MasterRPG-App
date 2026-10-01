// @copyright André Trettin

import Foundation
import Network
import Testing
@testable import GameRPG

/// CODE_AUDIT_15 §6.1: handshakes that are still in flight count against a source, because a
/// failure is only recorded once a handshake has ended.
@Suite("ConnectionThrottleTracker — pending handshake caps")
struct PendingHandshakeCapTests {
    private func endpoint(_ host: String) -> NWEndpoint {
        .hostPort(host: NWEndpoint.Host(host), port: 5000)
    }

    @Test("A single source may hold only a few unresolved handshakes at once")
    func perSourceCap() async {
        let sut = ConnectionThrottleTracker()
        let source = endpoint("10.0.0.5")
        var ids: [UUID] = []
        for _ in 0..<ConnectionThrottleTracker.maximumPendingHandshakesPerSource {
            #expect(await sut.shouldAllow(endpoint: source))
            let id = UUID()
            ids.append(id)
            await sut.register(id: id, endpoint: source)
        }
        #expect(await !sut.shouldAllow(endpoint: source))
        // Another source is unaffected.
        #expect(await sut.shouldAllow(endpoint: endpoint("10.0.0.6")))

        // Resolving one handshake frees a slot.
        await sut.resolve(id: ids[0], succeeded: true)
        #expect(await sut.shouldAllow(endpoint: source))
    }

    @Test("The total number of unresolved handshakes is capped across sources")
    func globalCap() async {
        let sut = ConnectionThrottleTracker()
        for index in 0..<ConnectionThrottleTracker.maximumPendingHandshakes {
            await sut.register(id: UUID(), endpoint: endpoint("10.1.0.\(index)"))
        }
        #expect(await !sut.shouldAllow(endpoint: endpoint("10.2.0.1")))
    }

    /// CODE_AUDIT_20 §6.1: a connection without a usable endpoint is throttled as one shared
    /// source instead of skipping every protection.
    @Test("Connections without an endpoint share one throttle source")
    func missingEndpointFailsClosed() async {
        let sut = ConnectionThrottleTracker()
        var ids: [UUID] = []
        for _ in 0..<ConnectionThrottleTracker.maximumPendingHandshakesPerSource {
            #expect(await sut.shouldAllow(endpoint: nil))
            let id = UUID()
            ids.append(id)
            await sut.register(id: id, endpoint: nil)
            #expect(await sut.isPending(id: id))
        }
        #expect(await !sut.shouldAllow(endpoint: nil))
        // A source with an endpoint is unaffected.
        #expect(await sut.shouldAllow(endpoint: endpoint("10.0.0.6")))
    }
}
