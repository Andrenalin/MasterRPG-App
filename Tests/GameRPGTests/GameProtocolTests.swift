// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// `GameProtocol.handleInput` hands `header.length` straight to
/// `deliverInputNoCopy` without a live `NWProtocolFramer.Instance` being
/// mockable, so this exercises the pulled-out length bound directly.
/// See CODE_AUDIT §5.9: an unbounded `UInt32` length let any TLS-authenticated
/// local-network peer force an effectively unbounded buffer wait.
@Suite("GameProtocol message-length bound")
struct GameProtocolTests {
    @Test("Zero-length messages are valid")
    func zeroLength() {
        #expect(GameProtocol.isMessageLengthValid(0))
    }

    @Test("A typical small message is valid")
    func typicalMessage() {
        #expect(GameProtocol.isMessageLengthValid(64 * 1_024))
    }

    @Test("Exactly the maximum is valid")
    func exactlyMaximum() {
        #expect(GameProtocol.isMessageLengthValid(GameProtocol.maximumMessageByteCount))
    }

    @Test("One byte past the maximum is rejected")
    func oneOverMaximum() {
        #expect(!GameProtocol.isMessageLengthValid(GameProtocol.maximumMessageByteCount + 1))
    }

    @Test("An adversarial near-4GB length is rejected")
    func adversarialLength() {
        #expect(!GameProtocol.isMessageLengthValid(UInt32.max))
    }
}
#endif
