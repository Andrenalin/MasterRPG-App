// @copyright André Trettin

import CryptoKit
import Foundation
import Network

protocol ConnectionAbstraction: AnyObject {
    var debugDescription: String { get }
    var stateUpdateHandler: (@Sendable (_ state: NWConnection.State) -> Void)? { get set }

    func cancel()
    func send(content: Data?, contentContext: NWConnection.ContentContext, isComplete: Bool, completion: NWConnection.SendCompletion)
    func start(queue: DispatchQueue)
    func receiveMessage(completion: @escaping @Sendable (_ completeContent: Data?, _ contentContext: NWConnection.ContentContext?, _ isComplete: Bool, _ error: NWError?) -> Void)
}

extension NWConnection: ConnectionAbstraction {}

extension NWConnection {
    static func connection(endpoint: NWEndpoint, passcode: String) -> NWConnection {
        NWConnection(to: endpoint, using: NWParameters(passcode: passcode))
    }
}

extension NWParameters {
    // Create parameters for use in PeerConnection and PeerListener.
    convenience init(passcode: String) {
        // Customize TCP options to enable keepalives.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2

        // Create parameters with custom TLS and TCP options.
        self.init(tls: NWParameters.tlsOptions(passcode: passcode), tcp: tcpOptions)

        // Enable using a peer-to-peer link.
        includePeerToPeer = true

        // Add your custom game protocol to support game messages.
        let gameOptions = NWProtocolFramer.Options(definition: GameProtocol.definition)
        defaultProtocolStack.applicationProtocols.insert(gameOptions, at: 0)
    }

    // Create TLS options using a passcode to derive a pre-shared key.
    private static func tlsOptions(passcode: String) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()

        // `Data(someString.utf8)` builds directly from the always-present UTF-8
        // view instead of the optional-returning, force-unwrapped
        // `.data(using: .utf8)!` — a Swift `String`'s UTF-8 encoding can't
        // actually fail, so this is the same bytes with no force-unwrap.
        let authenticationKey = SymmetricKey(data: Data(passcode.utf8))
        var authenticationCode = HMAC<SHA256>.authenticationCode(for: Data("GameMaster".utf8), using: authenticationKey)

        let authenticationDispatchData = withUnsafeBytes(of: &authenticationCode) { (ptr: UnsafeRawBufferPointer) in
            DispatchData(bytes: ptr)
        }

        // Both values below are derived from hardcoded constants, not
        // attacker-controlled input, so neither guard is expected to ever
        // fail in practice — but this connection-establishing security path
        // shouldn't force-unwrap even a constant, matching the discipline
        // already applied to `passcode` above. A guard failure here leaves
        // the PSK identity/ciphersuite unset, which fails the handshake
        // cleanly and visibly instead of crashing the app or silently
        // downgrading security. See CODE_AUDIT §5.3.
        guard let pskIdentity = stringToDispatchData("GameMaster") else {
            assertionFailure("stringToDispatchData(\"GameMaster\") unexpectedly failed to encode a constant string")
            return tlsOptions
        }
        guard let cipherSuite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) else {
            assertionFailure("TLS_PSK_WITH_AES_128_GCM_SHA256 unexpectedly failed to convert to tls_ciphersuite_t")
            return tlsOptions
        }

        sec_protocol_options_add_pre_shared_key(tlsOptions.securityProtocolOptions,
                                                authenticationDispatchData as __DispatchData,
                                                pskIdentity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tlsOptions.securityProtocolOptions,
                                                    cipherSuite)
        return tlsOptions
    }

    // Create a utility function to encode strings as pre-shared key data.
    private static func stringToDispatchData(_ string: String) -> DispatchData? {
        guard let stringData = string.data(using: .unicode) else {
            return nil
        }
        let dispatchData = withUnsafeBytes(of: stringData) { (ptr: UnsafeRawBufferPointer) in
            DispatchData(bytes: UnsafeRawBufferPointer(start: ptr.baseAddress, count: stringData.count))
        }
        return dispatchData
    }
}
