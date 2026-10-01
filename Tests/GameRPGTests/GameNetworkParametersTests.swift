// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import Testing

@testable import GameRPG

/// CODE_AUDIT_20 §4.5: peer-to-peer Wi-Fi joins depend on `includePeerToPeer` of the initial
/// parameters that `GameNetworkParameters.builder(passcode:)` builds on.
@Suite("Game network parameters")
struct GameNetworkParametersTests {
    @Test("The initial parameters of the game transport include the peer-to-peer link")
    func initialParametersIncludePeerToPeer() {
        let parameters = NWParameters(passcode: "1234")

        #expect(parameters.includePeerToPeer)
    }

    @Test("The TCP base keeps the keepalive schedule")
    func keepaliveIsEnabled() throws {
        let parameters = NWParameters(passcode: "1234")
        let tcp = try #require(parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)

        #expect(tcp.enableKeepalive)
        #expect(tcp.keepaliveIdle == Int(GameNetworkParameters.keepaliveIdle))
        #expect(tcp.keepaliveCount == Int(GameNetworkParameters.keepaliveCount))
    }
}
#endif
