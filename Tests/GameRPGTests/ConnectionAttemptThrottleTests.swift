// @copyright André Trettin

import Network
import Testing
@testable import GameRPG

@Suite("ConnectionAttemptThrottle — CODE_AUDIT §6.1")
struct ConnectionAttemptThrottleTests {
    @Test("Allows the first two failures from a source without throttling")
    func allowsFirstTwoFailures() async {
        let sut = ConnectionAttemptThrottle()
        #expect(await sut.shouldAllow(source: "1.2.3.4"))

        await sut.recordFailure(source: "1.2.3.4")
        #expect(await sut.shouldAllow(source: "1.2.3.4"))

        await sut.recordFailure(source: "1.2.3.4")
        #expect(await sut.shouldAllow(source: "1.2.3.4"))
    }

    @Test("Locks out a source only after the 3rd consecutive failure")
    func locksOutAfterThirdFailure() async {
        let sut = ConnectionAttemptThrottle()
        await sut.recordFailure(source: "1.2.3.4")
        await sut.recordFailure(source: "1.2.3.4")
        await sut.recordFailure(source: "1.2.3.4")

        #expect(await !sut.shouldAllow(source: "1.2.3.4"))
    }

    @Test("A success clears prior failures, so the source is no longer throttled")
    func successResetsFailureCount() async {
        let sut = ConnectionAttemptThrottle()
        await sut.recordFailure(source: "1.2.3.4")
        await sut.recordFailure(source: "1.2.3.4")
        await sut.recordSuccess(source: "1.2.3.4")
        await sut.recordFailure(source: "1.2.3.4")
        await sut.recordFailure(source: "1.2.3.4")

        // Two more failures after the reset is still below the 3-failure threshold.
        #expect(await sut.shouldAllow(source: "1.2.3.4"))
    }

    @Test("Throttling one source never affects another")
    func throttleIsPerSource() async {
        let sut = ConnectionAttemptThrottle()
        await sut.recordFailure(source: "1.2.3.4")
        await sut.recordFailure(source: "1.2.3.4")
        await sut.recordFailure(source: "1.2.3.4")

        #expect(await !sut.shouldAllow(source: "1.2.3.4"))
        #expect(await sut.shouldAllow(source: "5.6.7.8"))
    }

    @Test("Failures from long ago decay and never add up to a lockout")
    func oldFailuresDecay() async {
        let sut = ConnectionAttemptThrottle()
        let start = ContinuousClock.now
        await sut.recordFailure(source: "1.2.3.4", at: start)
        await sut.recordFailure(source: "1.2.3.4", at: start)
        let later = start.advanced(by: ConnectionAttemptThrottle.failureDecay + .seconds(1))

        await sut.recordFailure(source: "1.2.3.4", at: later)

        #expect(await sut.shouldAllow(source: "1.2.3.4", at: later))
    }

    @Test("A locked-out source is not evicted by a flood of throwaway sources")
    func lockoutSurvivesEvictionFlood() async {
        let sut = ConnectionAttemptThrottle()
        let start = ContinuousClock.now
        for _ in 0..<ConnectionAttemptThrottle.failureThreshold {
            await sut.recordFailure(source: "attacker", at: start)
        }

        for index in 0..<300 {
            await sut.recordFailure(source: "other-\(index)", at: start.advanced(by: .milliseconds(index + 1)))
        }

        #expect(await !sut.shouldAllow(source: "attacker", at: start.advanced(by: .seconds(1))))
    }

    @Test("IPv6 sources are keyed by /64 prefix, ignoring interface scope")
    func ipv6SourceKeyUsesPrefix() throws {
        func key(_ address: String) throws -> String? {
            let ipv6 = try #require(IPv6Address(address))
            return NWEndpoint.hostPort(host: .ipv6(ipv6), port: 1).throttleSourceKey
        }
        #expect(try key("2001:db8::1") == key("2001:db8::ffff"))
        #expect(try key("2001:db8::1") != key("2001:db9::1"))
        let ipv4 = try #require(IPv4Address("10.0.0.5"))
        #expect(NWEndpoint.hostPort(host: .ipv4(ipv4), port: 1).throttleSourceKey == "10.0.0.5")
    }
}
