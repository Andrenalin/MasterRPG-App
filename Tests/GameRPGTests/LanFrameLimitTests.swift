// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §5.1: the send side checks the limit the receiving framer enforces.
@Suite("LAN frame limit")
struct LanFrameLimitTests {
    @Test("A small package fits one message")
    func smallFits() {
        #expect(GameLimits.fitsOneMessage(payloadBytes: 0))
        #expect(GameLimits.fitsOneMessage(payloadBytes: 10 * ByteUnitForTests.megabyte))
    }

    @Test("Base64 makes a file of about 75 MB too large for a 100 MB frame")
    func base64InflationIsCounted() {
        // 74 MB -> ~98.7 MB encoded: still fits with the envelope allowance.
        #expect(GameLimits.fitsOneMessage(payloadBytes: 74 * ByteUnitForTests.megabyte))
        // 75 MB -> 100 MB encoded plus the envelope: past the receiver's limit.
        #expect(!GameLimits.fitsOneMessage(payloadBytes: 75 * ByteUnitForTests.megabyte))
        // 100 MB of raw bytes would have passed a check on the raw size.
        #expect(!GameLimits.fitsOneMessage(payloadBytes: GameLimits.maximumMessageBytes))
    }

    @Test("Nonsense sizes do not fit")
    func nonsenseDoesNotFit() {
        #expect(!GameLimits.fitsOneMessage(payloadBytes: -1))
        #expect(!GameLimits.fitsOneMessage(payloadBytes: .max))
    }

    @Test("What fits one message is accepted by the receiving framer")
    func sendLimitFollowsReceiveLimit() {
        let largest = stride(from: 0, through: 80 * ByteUnitForTests.megabyte, by: ByteUnitForTests.megabyte)
            .filter { GameLimits.fitsOneMessage(payloadBytes: $0) }.max() ?? 0
        let encodedBound = (largest + 2) / 3 * 4 + GameLimits.envelopeAllowanceBytes
        #expect(GameProtocol.isMessageLengthValid(UInt32(encodedBound)))
    }
}

private enum ByteUnitForTests {
    static let megabyte = 1_000_000
}
#endif
