// @copyright André Trettin

import Foundation
import Testing
@testable import CoreRPG

@Suite("Item transfer status")
struct ItemTransferStatusTests {
    @Test("A finished download reports its average rate")
    func finishedDownloadHasRate() {
        let status = ItemTransferStatus(state: .done, duration: .seconds(4), byteCount: 4_000_000)
        #expect(status.bytesPerSecond == 1_000_000)
    }

    @Test("A running, failed or unmeasured download has no rate")
    func otherStatesHaveNoRate() {
        #expect(ItemTransferStatus(state: .loading, duration: .seconds(10), byteCount: 100).bytesPerSecond == nil)
        #expect(ItemTransferStatus(state: .failed, duration: .seconds(180)).bytesPerSecond == nil)
        #expect(ItemTransferStatus(state: .done, duration: .zero, byteCount: 100).bytesPerSecond == nil)
        #expect(ItemTransferStatus(state: .done, duration: .seconds(1), byteCount: 0).bytesPerSecond == nil)
    }

    @Test("The summary names the time and the rate")
    func summaryNamesTimeAndRate() {
        let summary = ItemTransferStatus.summary(duration: .milliseconds(4200), byteCount: 5_460_000)
        #expect(summary.contains("4.2"))
        #expect(summary.contains("/s"))
        #expect(summary.contains("MB"))
    }

    @Test("The summary is only the time without bytes or time")
    func summaryWithoutRate() {
        #expect(!ItemTransferStatus.summary(duration: .seconds(3), byteCount: 0).contains("/s"))
        #expect(!ItemTransferStatus.summary(duration: .zero, byteCount: 100).contains("/s"))
    }
}
