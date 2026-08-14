// @copyright André Trettin

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
}
